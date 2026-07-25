import Foundation

/// What to hand to the OS in order to open an entry.
enum LaunchAction: Equatable {
    /// Let LaunchServices pick the browser. Only ever used for normal opens.
    case openWithSystemDefault(URL)
    /// Launch a specific browser with explicit arguments.
    ///
    /// The runner must pass `createsNewApplicationInstance = true`: measurement
    /// showed that with `false` the arguments do not reliably reach an
    /// already-running browser (Edge opened nothing; Chrome let the URL slip
    /// into whatever window was frontmost).
    case openApplication(bundleID: String, arguments: [String])
}

/// Why an entry cannot be opened as configured. Each case is a state the menu
/// shows as a disabled item with a reason — never a silent downgrade.
enum LaunchBlocked: Error, Equatable {
    case noPrivateBrowserConfigured
    case privateNotSupported(bundleID: String)
    case unknownBrowser(bundleID: String)
}

/// Turns a resolved plan into a concrete launch, entirely by table lookup.
enum LaunchPlanner {
    static func action(for url: URL, plan: OpenPlan) -> Result<LaunchAction, LaunchBlocked> {
        switch (plan.mode, plan.browser) {
        case (.normal, .systemDefault):
            return .success(.openWithSystemDefault(url))

        case (.normal, .bundleID(let bundleID)):
            return .success(.openApplication(bundleID: bundleID, arguments: [url.absoluteString]))

        case (.privateWindow, .systemDefault):
            // There is no way to ask LaunchServices for a private window, and
            // opening normally would defeat the point of the entry.
            return .failure(.noPrivateBrowserConfigured)

        case (.privateWindow, .bundleID(let bundleID)):
            guard let capability = BrowserCatalog.capability(forBundleID: bundleID) else {
                return .failure(.unknownBrowser(bundleID: bundleID))
            }
            guard let flag = capability.privateFlag else {
                return .failure(.privateNotSupported(bundleID: bundleID))
            }
            return .success(.openApplication(
                bundleID: bundleID,
                arguments: [flag, url.absoluteString]))
        }
    }

    /// The mode an Option-click asks for: the inverse of what was resolved.
    static func inverted(_ mode: OpenMode) -> OpenMode {
        mode == .normal ? .privateWindow : .normal
    }
}
