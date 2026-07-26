import AppKit

/// Everything the menu needs, with the OS behind protocols so the logic stays
/// testable.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var config: AppConfig
    private let configURL: URL
    let shelf: ShelfReading
    let inventory: BrowserInventory
    let launcher: BrowserLaunching
    let loginItem: LoginItemManaging

    init(
        configURL: URL = AppConfig.defaultFileURL(),
        shelf: ShelfReading = FileSystemShelf(),
        inventory: BrowserInventory = WorkspaceBrowserInventory(),
        launcher: BrowserLaunching = WorkspaceBrowserLauncher(),
        loginItem: LoginItemManaging = SMAppServiceLoginItem()
    ) {
        self.configURL = configURL
        self.shelf = shelf
        self.inventory = inventory
        self.launcher = launcher
        self.loginItem = loginItem
        config = AppConfig.read(contentsOf: configURL)
    }

    var rootURL: URL? { config.rootURL }

    /// Re-read on every menu open, so hand-edits to the config file take effect
    /// without restarting — the file is meant to be edited.
    func reloadConfig() {
        config = AppConfig.read(contentsOf: configURL)
    }

    func setRoot(_ url: URL) throws {
        config.rootPath = url.path
        try config.write(to: configURL)
    }

    func setInbox(_ path: String) throws {
        config.inbox = path
        try config.write(to: configURL)
    }

    func setNormalBrowser(_ selection: BrowserSelection) throws {
        config.normalBrowser = selection
        try config.write(to: configURL)
    }

    /// `nil` clears the choice, which leaves private entries disabled rather
    /// than opening them in the normal browser.
    func setPrivateBrowser(_ bundleID: String?) throws {
        config.privateBrowser = bundleID
        try config.write(to: configURL)
    }

    /// True when private entries cannot be honoured only because nothing has
    /// been chosen yet — as opposed to no capable browser being installed.
    var needsPrivateBrowserChoice: Bool {
        config.privateBrowser == nil && !inventory.privateCapableBrowsers().isEmpty
    }

    // MARK: - Entries

    /// Both ways an entry can be opened: as configured, and as an Option-click
    /// would ask for. Computed together so the menu can disable the one that is
    /// impossible instead of discovering it after the click.
    struct EntryPlan {
        let target: URL
        let resolvedMode: OpenMode
        let asResolved: Result<LaunchAction, LaunchBlocked>
        let inverted: Result<LaunchAction, LaunchBlocked>
    }

    func plan(forEntryAt fileURL: URL, in folderURL: URL) throws -> EntryPlan {
        let entry = try WeblocFile.read(contentsOf: fileURL)
        let chain = rootURL.map { shelf.defaultsChain(from: $0, to: folderURL) } ?? []
        let plan = MetadataResolver.resolve(entry: entry, folderChain: chain, config: config)
        let flipped = OpenPlan(
            mode: LaunchPlanner.inverted(plan.mode),
            browser: browser(for: LaunchPlanner.inverted(plan.mode), keeping: plan))

        return EntryPlan(
            target: entry.url,
            resolvedMode: plan.mode,
            asResolved: LaunchPlanner.action(for: entry.url, plan: plan),
            inverted: LaunchPlanner.action(for: entry.url, plan: flipped))
    }

    /// An Option-click changes the mode, so the browser has to be re-picked: the
    /// browser resolved for a normal open may have no private mode at all, and
    /// the private browser is not the right choice for a normal open.
    private func browser(for mode: OpenMode, keeping plan: OpenPlan) -> BrowserSelection {
        switch mode {
        case .normal:
            return config.normalBrowser
        case .privateWindow:
            if case .bundleID(let id) = plan.browser,
               BrowserCatalog.capability(forBundleID: id)?.supportsPrivate == true {
                return .bundleID(id)
            }
            return config.privateBrowser.map(BrowserSelection.bundleID) ?? .systemDefault
        }
    }

    // MARK: - Creating entries

    /// Where a dropped URL lands: the configured inbox, or the root itself.
    func inboxURL() throws -> URL {
        guard let root = rootURL else { throw ShelfError.noRootConfigured }
        let trimmed = config.inbox.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return root }

        let inbox = root.appendingPathComponent(trimmed)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    @discardableResult
    func addEntry(
        url: URL,
        name: String? = nil,
        in folder: URL,
        openMode: OpenMode? = nil,
        browserBundleID: String? = nil
    ) throws -> URL {
        let base = EntryNaming.filename(for: url, preferred: name)
        let fileURL = EntryNaming.uniqueURL(in: folder, base: base, extension: "webloc")
        try WeblocFile(url: url, openMode: openMode, browserBundleID: browserBundleID)
            .write(to: fileURL)
        didChangeShelf()
        return fileURL
    }

    /// Every folder under the root, depth-first, for the destination picker.
    /// Returned paths are relative to the root; the root itself is `""`.
    ///
    /// Memoized per revision: pickers call this from their view bodies, and it
    /// walks the whole folder.
    func folderPaths() -> [String] {
        if let cached = cachedFolderPaths, cached.revision == revision { return cached.paths }

        let paths = walkFolderPaths()
        cachedFolderPaths = (revision, paths)
        return paths
    }

    private var cachedFolderPaths: (revision: Int, paths: [String])?

    private func walkFolderPaths() -> [String] {
        guard let root = rootURL else { return [] }
        var paths = [""]

        func walk(_ folder: URL, prefix: String) {
            let children = (try? shelf.children(of: folder)) ?? []
            for case .folder(let name, let url) in children {
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                paths.append(path)
                walk(url, prefix: path)
            }
        }
        walk(root, prefix: "")
        return paths
    }

    func url(forFolderPath path: String) -> URL? {
        guard let root = rootURL else { return nil }
        return path.isEmpty ? root : root.appendingPathComponent(path)
    }

    /// Bumped whenever the shelf changes, so cached views reload.
    @Published private(set) var revision = 0

    private func didChangeShelf() {
        revision += 1
    }

    // MARK: - Launching

    func run(_ action: LaunchAction) {
        do {
            try launcher.run(action)
        } catch {
            present(error)
        }
    }

    func present(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not open the entry"
        alert.informativeText = Self.describe(error)
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func describe(_ error: Error) -> String {
        switch error {
        case LaunchBlocked.noPrivateBrowserConfigured:
            return "No browser is set for private entries. "
                + "Choose one that supports private windows (Firefox, Chrome, or Edge)."
        case LaunchBlocked.privateNotSupported(let bundleID):
            return "\(BrowserCatalog.displayName(forBundleID: bundleID)) offers no supported way "
                + "to open a private window from another app."
        case LaunchBlocked.unknownBrowser(let bundleID):
            return "url-shelf does not know how to drive \(bundleID)."
        case LaunchError.browserNotInstalled(let bundleID):
            return "\(BrowserCatalog.displayName(forBundleID: bundleID)) is not installed."
        default:
            return error.localizedDescription
        }
    }
}
