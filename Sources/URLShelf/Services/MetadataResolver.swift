import Foundation

/// The decision of how a single entry should be opened, before availability on
/// this machine is considered.
struct OpenPlan: Equatable {
    var mode: OpenMode
    var browser: BrowserSelection
}

/// Resolves an entry's effective settings.
///
/// Order is **entry > nearest ancestor folder > global config**, and that is the
/// whole hierarchy — there is deliberately no fourth layer. The folder chain is
/// passed root-first, so later elements are nearer the entry and win.
enum MetadataResolver {
    static func resolve(
        entryMode: OpenMode?,
        entryBrowser: String?,
        folderChain: [FolderDefaults],
        config: AppConfig
    ) -> OpenPlan {
        let folderMode = folderChain.compactMap(\.openMode).last
        let folderBrowser = folderChain.compactMap(\.browserBundleID).last

        let mode = entryMode ?? folderMode ?? .normal

        if let bundleID = entryBrowser ?? folderBrowser {
            return OpenPlan(mode: mode, browser: .bundleID(bundleID))
        }

        switch mode {
        case .normal:
            return OpenPlan(mode: mode, browser: config.normalBrowser)
        case .privateWindow:
            // No implicit fall back to the normal browser: a private entry with
            // no private browser configured must surface as unavailable, not as
            // a normal-session open.
            let browser = config.privateBrowser.map(BrowserSelection.bundleID) ?? .systemDefault
            return OpenPlan(mode: mode, browser: browser)
        }
    }

    /// Convenience for an entry already read from disk.
    static func resolve(
        entry: WeblocFile,
        folderChain: [FolderDefaults],
        config: AppConfig
    ) -> OpenPlan {
        resolve(
            entryMode: entry.openMode,
            entryBrowser: entry.browserBundleID,
            folderChain: folderChain,
            config: config)
    }
}
