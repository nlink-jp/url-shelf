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
    let editor: ShelfEditing

    init(
        configURL: URL = AppConfig.defaultFileURL(),
        shelf: ShelfReading = FileSystemShelf(),
        inventory: BrowserInventory = WorkspaceBrowserInventory(),
        launcher: BrowserLaunching = WorkspaceBrowserLauncher(),
        loginItem: LoginItemManaging = SMAppServiceLoginItem(),
        editor: ShelfEditing = FileSystemShelfEditor()
    ) {
        self.configURL = configURL
        self.shelf = shelf
        self.inventory = inventory
        self.launcher = launcher
        self.loginItem = loginItem
        self.editor = editor
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
    func folderPaths() -> [String] {
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

    // MARK: - Editing the shelf

    /// Bumped after every mutation so views reload the tree. The filesystem is
    /// still the only source of truth — this is a "look again" signal, not state.
    @Published private(set) var revision = 0

    func tree() -> ShelfNode? {
        rootURL.map { shelf.tree(at: $0, name: "Shelf") }
    }

    func entry(at fileURL: URL) throws -> WeblocFile {
        try WeblocFile.read(contentsOf: fileURL)
    }

    func folderDefaults(at folder: URL) -> FolderDefaults {
        shelf.defaults(at: folder)
    }

    func updateEntry(
        at fileURL: URL,
        url: URL? = nil,
        openMode: OpenMode?? = nil,
        browserBundleID: String?? = nil
    ) throws {
        var entry = try WeblocFile.read(contentsOf: fileURL)
        if let url { entry.url = url }
        if let openMode { entry.openMode = openMode }
        if let browserBundleID { entry.browserBundleID = browserBundleID }
        try entry.write(to: fileURL)
        didChangeShelf()
    }

    /// Writing empty defaults removes the file rather than leaving an inert one:
    /// the shelf should not accumulate files that say nothing.
    func setFolderDefaults(_ defaults: FolderDefaults, at folder: URL) throws {
        let fileURL = folder.appendingPathComponent(FolderDefaults.filename)
        if defaults.isEmpty {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } else {
            try defaults.serialized().write(to: fileURL, atomically: true, encoding: .utf8)
        }
        didChangeShelf()
    }

    @discardableResult
    func createFolder(named name: String, in parent: URL) throws -> URL {
        defer { didChangeShelf() }
        return try editor.createFolder(named: name, in: parent)
    }

    @discardableResult
    func rename(_ url: URL, toDisplayName newName: String) throws -> URL {
        defer { didChangeShelf() }
        return try editor.rename(url, toDisplayName: newName)
    }

    @discardableResult
    func move(_ url: URL, to destination: URL) throws -> URL {
        defer { didChangeShelf() }
        return try editor.move(url, to: destination)
    }

    func trash(_ url: URL) throws {
        defer { didChangeShelf() }
        try editor.trash(url)
    }

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
