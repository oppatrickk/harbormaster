import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService` (the modern replacement for `SMLoginItemSetEnabled`
/// and the `LSSharedFileList` login-item APIs).
///
/// SMAppService requires a code-signed bundle. An ad-hoc signed build usually works once the
/// app lives in `/Applications`, but macOS is inconsistent about it — see README. Errors are
/// surfaced to the caller rather than swallowed so the UI can explain a failure instead of
/// silently flipping the toggle back.
enum LoginItem {
    /// SMAppService is the source of truth; nothing is mirrored into UserDefaults.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            // unregister() throws if it was never registered; that's already the goal state.
            guard service.status == .enabled else { return }
            try service.unregister()
        }
    }

    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled:
            return "Enabled"
        case .notRegistered:
            return "Not enabled"
        case .notFound:
            return "Not found — run the app from /Applications"
        case .requiresApproval:
            return "Needs approval in System Settings › General › Login Items"
        @unknown default:
            return "Unknown"
        }
    }
}
