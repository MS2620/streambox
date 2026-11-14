import SwiftUI

/// Colours and small building blocks shared by every screen.
enum Theme {
    /// The page background that hero artwork fades into.
    static let base = Color(red: 0.055, green: 0.065, blue: 0.09)
    static let glass = Color.white.opacity(0.12)
    static let glassStrong = Color.white.opacity(0.2)
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.1)
    static let live = Color(red: 1, green: 0.3, blue: 0.3)
    /// Text of rows that delete something, on glass.
    static let danger = Color(red: 1, green: 0.54, blue: 0.54)
    /// The same rows while focused (white background).
    static let dangerInk = Color(red: 0.75, green: 0.1, blue: 0.1)
    /// Status dots.
    static let good = Color(red: 0.29, green: 0.87, blue: 0.5)
    static let warning = Color(red: 1, green: 0.75, blue: 0.3)
}

extension Color {
    /// A colour from a hex string such as "da020e" or "#DA020E".
    init?(hex: String?) {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

/// The soft, frosted backdrop behind Live TV, Sports, Calendar, Search and Settings.
struct AppBackground: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ZStack {
            if settings.prefs.backgroundStyle == .frosted {
                Color(red: 0.2, green: 0.24, blue: 0.31)
                RadialGradient(colors: [Color(red: 0.62, green: 0.5, blue: 0.45).opacity(0.55), .clear],
                               center: UnitPoint(x: 0.72, y: 0.3), startRadius: 0, endRadius: 900)
                RadialGradient(colors: [Color(red: 0.35, green: 0.5, blue: 0.7).opacity(0.6), .clear],
                               center: UnitPoint(x: 0.1, y: 0.15), startRadius: 0, endRadius: 800)
                RadialGradient(colors: [Color(red: 0.55, green: 0.4, blue: 0.55).opacity(0.4), .clear],
                               center: UnitPoint(x: 0.45, y: 0.95), startRadius: 0, endRadius: 800)
                LinearGradient(colors: [.clear, Theme.base.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            } else {
                Theme.base
            }
        }
        .ignoresSafeArea()
    }
}

/// A button style with no system chrome: the label draws its own focus state.
struct PlainPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Wraps card artwork: white outline, lift and shadow while focused.
struct FocusFrame<Content: View>: View {
    let cornerRadius: CGFloat
    let content: Content
    @Environment(\.isFocused) private var isFocused

    init(cornerRadius: CGFloat = 18, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white, lineWidth: isFocused ? 5 : 0)
            )
            .scaleEffect(isFocused ? 1.06 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, y: 12)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A small rounded tag ("4K", "Drama", "★ 8.4").
struct Chip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 20, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.glassStrong, in: Capsule())
    }
}

/// A rounded pill button label that turns white while focused.
struct PillLabel: View {
    let title: String
    var icon: String? = nil
    var selected = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon).font(.system(size: 24, weight: .semibold))
            }
            Text(title).font(.system(size: 24, weight: .semibold)).lineLimit(1)
        }
        .foregroundStyle(isFocused ? Theme.ink : Color.white)
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(
            Capsule().fill(isFocused ? Color.white : (selected ? Theme.glassStrong : Theme.glass))
        )
        .scaleEffect(isFocused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

/// A glass card that groups rows, with an optional small uppercase header.
struct GlassPanel<Content: View>: View {
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.horizontal, 22)
                    .padding(.bottom, 6)
            }
            content
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 34, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

/// A list row inside a glass panel: optional icon or logo, title, subtitle and
/// a trailing note. The whole row turns white while focused.
struct ListRowLabel: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var logoURL: URL? = nil
    var showsLogo = false
    var trailing: String? = nil
    var trailingIcon: String? = nil
    var selected = false
    var dimmed = false
    /// Red text, for rows that delete something.
    var destructive = false
    @Environment(\.isFocused) private var isFocused

    private var restingColor: Color {
        if destructive { return Theme.danger }
        return Color.white.opacity(dimmed ? 0.55 : 1)
    }

    var body: some View {
        HStack(spacing: 18) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .frame(width: 36)
            }
            if showsLogo {
                AsyncImage(url: logoURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.glassStrong)
                }
                .frame(width: 70, height: 42)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 20, weight: .medium))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 22, weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
            }
            if let trailingIcon {
                Image(systemName: trailingIcon).font(.system(size: 24, weight: .semibold))
            }
        }
        .foregroundStyle(isFocused ? (destructive ? Theme.dangerInk : Theme.ink) : restingColor)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isFocused ? Color.white : (selected ? Theme.glassStrong : Color.clear))
        )
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

/// A thin progress bar.
struct ThinProgress: View {
    let fraction: Double
    var tint: Color = .white

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.25))
                Capsule().fill(tint).frame(width: geo.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 8)
    }
}

/// A sheet that asks for one line of text: a folder name, a server, a password…
struct NameSheet: View {
    let title: String
    let placeholder: String
    let secure: Bool
    let allowsEmpty: Bool
    let autocapitalize: Bool
    let onSave: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String = "", placeholder: String = "Name", secure: Bool = false,
         allowsEmpty: Bool = false, autocapitalize: Bool = true, onSave: @escaping (String) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.secure = secure
        self.allowsEmpty = allowsEmpty
        self.autocapitalize = autocapitalize
        self.onSave = onSave
        self._text = State(initialValue: initial)
    }

    /// Passwords are kept exactly as typed; everything else loses stray spaces.
    private var value: String { secure ? text : text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 40) {
            Text(title).font(.title2).bold()
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(autocapitalize ? .words : .never)
                }
            }
            .autocorrectionDisabled(!autocapitalize)
            .frame(maxWidth: 900)
            HStack(spacing: 40) {
                Button("Save") {
                    onSave(value)
                    dismiss()
                }
                .disabled(!allowsEmpty && value.isEmpty)
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding(80)
    }
}

/// Lays its children out in rows, wrapping to a new row when one is full
/// (filter buttons that don't fit on one line).
struct FlowLayout: Layout {
    var spacing: CGFloat = 12
    var rowSpacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                y += rowHeight + rowSpacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + rowSpacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
