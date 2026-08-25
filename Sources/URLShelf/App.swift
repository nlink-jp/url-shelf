import AppKit

enum AppInfo {
    /// The app's short version (from Info.plist), with any leading "v" stripped.
    /// Falls back to "dev" when run without a bundle (e.g. `swift run`).
    static var version: String {
        let raw = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
        return raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
    }
}

/// AppKit-hosted entry point rather than a SwiftUI `App`.
///
/// The menu bar item is an `NSStatusItem` because three required behaviours have
/// no SwiftUI equivalent: lazy submenu population per folder (`NSMenuDelegate`),
/// Option-key alternate items for the normal/private inversion, and accepting a
/// URL dropped onto the status item's view. SwiftUI is still used inside the
/// settings window via `NSHostingView`.
@main
enum URLShelfMain {
    /// `NSApplication.delegate` is a weak reference — the delegate must be owned here.
    private static var delegate: AppDelegate?

    static func main() {
        // Two instances would stack two menu bar items. LSMultipleInstances-
        // Prohibited (Info.plist) stops LaunchServices launches; this guard
        // stops the rest (direct exec, `open -n`).
        let bundleID = Bundle.main.bundleIdentifier
        let instancePIDs = bundleID.map { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .map(\.processIdentifier)
        } ?? []
        if case .exitDuplicate(let message) = singleInstanceDecision(
            bundleID: bundleID,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            instancePIDs: instancePIDs
        ) {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(0)
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = StatusItemController(model: AppModel())
    }
}
