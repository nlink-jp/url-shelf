import AppKit

enum LaunchError: Error, Equatable {
    case browserNotInstalled(bundleID: String)
}

protocol BrowserLaunching {
    func run(_ action: LaunchAction) throws
}

/// Runs a `LaunchAction` through `NSWorkspace`.
///
/// `createsNewApplicationInstance = true` is not optional. Measured on
/// macOS 26.5.2: with it, a transient process forwards the arguments to the
/// running browser and exits immediately (the `open -na` behaviour). Without it,
/// Edge opened nothing at all and Chrome delivered the URL to whatever window
/// happened to be frontmost, ignoring the flag.
final class WorkspaceBrowserLauncher: BrowserLaunching {
    private let workspace: NSWorkspace
    /// Failures reported after the launch is already under way (the browser
    /// crashed on start, the bundle was replaced mid-flight, …).
    var onAsyncFailure: ((Error) -> Void)?

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func run(_ action: LaunchAction) throws {
        switch action {
        case .openWithSystemDefault(let url):
            workspace.open(url)

        case .openApplication(let bundleID, let arguments):
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
                throw LaunchError.browserNotInstalled(bundleID: bundleID)
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = arguments
            configuration.createsNewApplicationInstance = true
            configuration.activates = true

            workspace.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
                if let error { self?.onAsyncFailure?(error) }
            }
        }
    }
}

/// Installed-browser detection backed by LaunchServices.
struct WorkspaceBrowserInventory: BrowserInventory {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func isInstalled(bundleID: String) -> Bool {
        workspace.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}
