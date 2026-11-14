import SwiftUI
import UIKit
import Libmpv

// Based on the MPVKit tvOS demo (Metal / MoltenVK renderer).

/// Workaround for MoltenVK setting drawableSize to 1x1, which causes flicker.
/// https://github.com/mpv-player/mpv/pull/13651
final class MPVMetalLayer: CAMetalLayer {
    override var drawableSize: CGSize {
        get { super.drawableSize }
        set {
            if Int(newValue.width) > 1 && Int(newValue.height) > 1 {
                super.drawableSize = newValue
            }
        }
    }
}

/// Playback state published to SwiftUI. Only mutated on the main thread.
final class MPVPlayerState: ObservableObject {
    @Published var position: Double = 0
    @Published var duration: Double = 0
    @Published var paused = false
    @Published var buffering = true
    @Published var error: String?
    @Published var ended = false
}

/// Lets SwiftUI reach the controller to send commands.
final class MPVHandle: ObservableObject {
    weak var controller: MPVViewController?
}

struct MPVVideoView: UIViewControllerRepresentable {
    let url: URL
    let state: MPVPlayerState
    let handle: MPVHandle

    func makeUIViewController(context: Context) -> MPVViewController {
        let controller = MPVViewController(url: url, state: state)
        handle.controller = controller
        return controller
    }

    func updateUIViewController(_ controller: MPVViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: MPVViewController, coordinator: ()) {
        controller.shutdown()
    }
}

final class MPVViewController: UIViewController {
    var metalLayer = MPVMetalLayer()
    var mpv: OpaquePointer?
    private lazy var queue = DispatchQueue(label: "streambox.mpv", qos: .userInitiated)
    private let url: URL
    private let state: MPVPlayerState

    init(url: URL, state: MPVPlayerState) {
        self.url = url
        self.state = state
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        metalLayer.frame = view.bounds
        metalLayer.contentsScale = UIScreen.main.nativeScale
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        setupMpv()
        command("loadfile", args: [url.absoluteString, "replace"])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        metalLayer.frame = view.bounds
    }

    // MARK: - Setup

    private func setupMpv() {
        guard let handle = mpv_create() else {
            state.error = "Could not start the player."
            return
        }
        mpv = handle

        mpv_request_log_messages(handle, "warn")

        // Rendering: Vulkan via MoltenVK onto our Metal layer, hardware decoding via VideoToolbox.
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &metalLayer))
        setOption("vo", "gpu-next")
        setOption("gpu-api", "vulkan")
        setOption("gpu-context", "moltenvk")
        setOption("hwdec", "videotoolbox")
        setOption("video-rotate", "no")

        // Subtitles / audio language preferences
        setOption("subs-match-os-language", "yes")
        setOption("subs-fallback", "yes")
        setOption("slang", "en,eng")
        setOption("alang", "en,eng")

        // Networking / caching for debrid + IPTV
        setOption("cache", "yes")
        setOption("demuxer-max-bytes", "150MiB")
        setOption("demuxer-max-back-bytes", "50MiB")
        setOption("network-timeout", "30")
        setOption("user-agent", "Mozilla/5.0 (AppleTV) StreamBox/0.1")

        // On-screen messages (track switches etc.)
        setOption("osd-level", "1")
        setOption("osd-font-size", "40")

        checkError(mpv_initialize(handle))

        mpv_observe_property(handle, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "paused-for-cache", MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, "core-idle", MPV_FORMAT_FLAG)

        // Retained until MPV_EVENT_SHUTDOWN so the callback never sees a freed controller.
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx else { return }
            let controller = Unmanaged<MPVViewController>.fromOpaque(ctx).takeUnretainedValue()
            controller.readEvents()
        }, Unmanaged.passRetained(self).toOpaque())

        NotificationCenter.default.addObserver(self, selector: #selector(enterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc private func enterBackground() {
        // Avoids a black screen when returning to the app.
        setFlag("pause", true)
        setOption("vid", "no")
    }

    @objc private func enterForeground() {
        setOption("vid", "auto")
        setFlag("pause", false)
    }

    // MARK: - Controls

    func togglePause() {
        command("cycle", args: ["pause"])
    }

    func seek(by seconds: Double) {
        command("osd-msg-bar", args: ["seek", String(seconds), "relative"])
    }

    /// Cycles "sub" or "audio" and shows the new track on screen.
    func cycle(_ property: String) {
        command("osd-msg", args: ["cycle", property])
    }

    func shutdown() {
        NotificationCenter.default.removeObserver(self)
        command("quit", checkForErrors: false)
    }

    // MARK: - mpv helpers

    private func setOption(_ name: String, _ value: String) {
        guard let mpv else { return }
        checkError(mpv_set_option_string(mpv, name, value))
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int32 = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    func command(_ command: String, args: [String] = [], checkForErrors: Bool = true) {
        guard let mpv else { return }
        let strings = [command] + args
        var cargs: [UnsafePointer<CChar>?] = strings.map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer {
            for pointer in cargs where pointer != nil {
                free(UnsafeMutablePointer(mutating: pointer))
            }
        }
        let result = mpv_command(mpv, &cargs)
        if checkForErrors { checkError(result) }
    }

    private func checkError(_ status: CInt) {
        if status < 0 {
            print("[mpv] API error: \(String(cString: mpv_error_string(status)))")
        }
    }

    // MARK: - Events

    func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let handle = self.mpv {
                guard let event = mpv_wait_event(handle, 0) else { break }
                let id = event.pointee.event_id
                if id == MPV_EVENT_NONE { break }

                switch id {
                case MPV_EVENT_PROPERTY_CHANGE:
                    if let property = UnsafePointer<mpv_event_property>(OpaquePointer(event.pointee.data))?.pointee {
                        self.handleProperty(property)
                    }

                case MPV_EVENT_FILE_LOADED:
                    DispatchQueue.main.async { self.state.buffering = false }

                case MPV_EVENT_END_FILE:
                    if let end = UnsafePointer<mpv_event_end_file>(OpaquePointer(event.pointee.data))?.pointee {
                        if end.reason == MPV_END_FILE_REASON_ERROR {
                            let message = String(cString: mpv_error_string(end.error))
                            DispatchQueue.main.async {
                                self.state.error = "mpv: \(message)"
                                self.state.buffering = false
                            }
                        } else if end.reason == MPV_END_FILE_REASON_EOF {
                            DispatchQueue.main.async { self.state.ended = true }
                        }
                    }

                case MPV_EVENT_LOG_MESSAGE:
                    if let msg = UnsafePointer<mpv_event_log_message>(OpaquePointer(event.pointee.data))?.pointee,
                       let prefix = msg.prefix, let text = msg.text {
                        print("[mpv:\(String(cString: prefix))] \(String(cString: text))", terminator: "")
                    }

                case MPV_EVENT_SHUTDOWN:
                    mpv_terminate_destroy(handle)
                    self.mpv = nil
                    // Balances passRetained in setupMpv.
                    Unmanaged.passUnretained(self).release()
                    return

                default:
                    break
                }
            }
        }
    }

    private func handleProperty(_ property: mpv_event_property) {
        let name = String(cString: property.name)
        guard let data = property.data, property.format != MPV_FORMAT_NONE else { return }

        switch name {
        case "time-pos":
            let value = data.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { self.state.position = value }
        case "duration":
            let value = data.assumingMemoryBound(to: Double.self).pointee
            DispatchQueue.main.async { self.state.duration = value }
        case "pause":
            let value = data.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { self.state.paused = value }
        case "paused-for-cache":
            let value = data.assumingMemoryBound(to: Int32.self).pointee != 0
            DispatchQueue.main.async { self.state.buffering = value }
        default:
            break
        }
    }
}
