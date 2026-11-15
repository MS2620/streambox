import Foundation
import Sentry

/// Crash reports through Sentry. A report holds where in Tellio's code it crashed and the
/// tvOS version and model. Nothing else: no logins, links (stream links carry IPTV logins),
/// server or channel names, IP address or watch history.
enum CrashReporting {
    /// Filled at build time from the SENTRY_DSN secret; empty in builds without it.
    static var dsn: String {
        (Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var isAvailable: Bool { dsn.hasPrefix("https://") }

    /// Starts or stops reporting to match the setting. A crash is sent the next time Tellio opens.
    static func apply(enabled: Bool) {
        guard isAvailable else { return }
        if enabled {
            guard !SentrySDK.isEnabled else { return }
            SentrySDK.start { options in
                options.dsn = dsn
                options.debug = false
                options.sendDefaultPii = false              // no IP address or device name
                options.enableAutoBreadcrumbTracking = false
                options.enableNetworkBreadcrumbs = false    // no request addresses
                options.enableNetworkTracking = false
                options.enableCaptureFailedRequests = false
                options.beforeBreadcrumb = { _ in nil }
                options.beforeSend = { event in scrub(event) }
            }
        } else if SentrySDK.isEnabled {
            SentrySDK.close()
        }
    }

    /// Last line of defence: strip anything personal before a report leaves the Apple TV.
    private static func scrub(_ event: Event) -> Event {
        event.user = nil
        event.request = nil
        event.breadcrumbs = nil
        event.serverName = nil
        event.extra = nil
        if let message = event.message {
            event.message = SentryMessage(formatted: clean(message.formatted))
        }
        for exception in event.exceptions ?? [] {
            if let value = exception.value(forKey: "value") as? String {
                exception.setValue(clean(value), forKey: "value")
            }
        }
        return event
    }

    /// Removes links, IP addresses and anything that looks like a login.
    static func clean(_ text: String) -> String {
        var text = text
        let patterns: [(String, String)] = [
            (#"[a-zA-Z][a-zA-Z0-9+.-]*://\S+"#, "[link]"),
            (#"\b\d{1,3}(\.\d{1,3}){3}(:\d+)?\b"#, "[address]"),
            (#"(?i)\b(user(name)?|pass(word)?|token|key)\s*[=:]\s*\S+"#, "$1=[removed]"),
        ]
        for (pattern, replacement) in patterns {
            text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return text
    }
}
