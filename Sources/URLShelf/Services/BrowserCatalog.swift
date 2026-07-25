import Foundation

/// A browser url-shelf knows how to drive.
struct BrowserCapability: Equatable {
    let bundleID: String
    let displayName: String
    /// The flag that forces a private window, or `nil` when the browser offers
    /// no supported way to be opened privately from outside.
    let privateFlag: String?

    var supportsPrivate: Bool { privateFlag != nil }
}

/// The private-launch capability table.
///
/// **Every entry here was measured, never assumed** (`spikes/launch-probe.swift`).
/// A wrong flag does not raise an error — the browser silently opens the URL in a
/// normal window, which is exactly the accident this app exists to prevent. Note
/// that Firefox takes a Mozilla-style *single* dash: the GNU-style
/// `--private-window` is accepted and ignored.
enum BrowserCatalog {
    static let all: [BrowserCapability] = [
        BrowserCapability(
            bundleID: "org.mozilla.firefox",
            displayName: "Firefox",
            privateFlag: "-private-window"),
        BrowserCapability(
            bundleID: "com.google.Chrome",
            displayName: "Google Chrome",
            privateFlag: "--incognito"),
        BrowserCapability(
            bundleID: "com.microsoft.edgemac",
            displayName: "Microsoft Edge",
            privateFlag: "--inprivate"),
        BrowserCapability(
            bundleID: "com.brave.Browser",
            displayName: "Brave",
            privateFlag: "--incognito"),
        BrowserCapability(
            bundleID: "com.vivaldi.Vivaldi",
            displayName: "Vivaldi",
            privateFlag: "--incognito"),
        BrowserCapability(
            bundleID: "com.apple.Safari",
            displayName: "Safari",
            privateFlag: nil),
    ]

    static func capability(forBundleID bundleID: String) -> BrowserCapability? {
        all.first { $0.bundleID == bundleID }
    }

    static func displayName(forBundleID bundleID: String) -> String {
        capability(forBundleID: bundleID)?.displayName ?? bundleID
    }
}

/// Which of the catalogued browsers are actually present on this machine.
protocol BrowserInventory {
    func isInstalled(bundleID: String) -> Bool
}

extension BrowserInventory {
    /// Browsers offered for normal opening.
    func installedBrowsers() -> [BrowserCapability] {
        BrowserCatalog.all.filter { isInstalled(bundleID: $0.bundleID) }
    }

    /// Browsers offered for private opening. Empty means private entries cannot
    /// be honoured on this machine and must be shown disabled.
    func privateCapableBrowsers() -> [BrowserCapability] {
        installedBrowsers().filter(\.supportsPrivate)
    }
}
