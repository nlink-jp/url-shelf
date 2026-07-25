import Foundation
import ServiceManagement

/// Registers the app to start at login.
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    /// Whether the OS can register a login item at all — it cannot for a bare
    /// `swift run` binary, only for a real `.app` bundle.
    var isAvailable: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// `SMAppService` (macOS 13+) — no helper bundle, no deprecated
/// `SMLoginItemSetEnabled`, and the user can override it in System Settings.
struct SMAppServiceLoginItem: LoginItemManaging {
    var isAvailable: Bool {
        // Bundle.main.bundleIdentifier is nil for a bare executable, and
        // SMAppService then has nothing to register.
        Bundle.main.bundleIdentifier != nil
    }

    var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else { return }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
