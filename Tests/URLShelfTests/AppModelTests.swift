import XCTest
@testable import URLShelf

private struct FakeShelf: ShelfReading {
    var defaultsByPath: [String: FolderDefaults] = [:]
    func children(of folder: URL) throws -> [ShelfItem] { [] }
    func defaults(at folder: URL) -> FolderDefaults {
        defaultsByPath[folder.lastPathComponent] ?? .empty
    }
}

private struct FakeInventory: BrowserInventory {
    let installed: Set<String>
    func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}

private final class SpyLauncher: BrowserLaunching {
    var actions: [LaunchAction] = []
    func run(_ action: LaunchAction) throws { actions.append(action) }
}

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configURL = root.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(
        normal: String = "default",
        private privateBrowser: String = "org.mozilla.firefox",
        shelf: FakeShelf = FakeShelf(),
        installed: Set<String> = ["org.mozilla.firefox", "com.apple.Safari"],
        launcher: SpyLauncher = SpyLauncher()
    ) throws -> AppModel {
        try """
        [shelf]
        root    = \(MiniTOML.quote(root.path))

        [browser]
        normal  = \(MiniTOML.quote(normal))
        private = \(MiniTOML.quote(privateBrowser))
        """.write(to: configURL, atomically: true, encoding: .utf8)

        return AppModel(
            configURL: configURL,
            shelf: shelf,
            inventory: FakeInventory(installed: installed),
            launcher: launcher)
    }

    @discardableResult
    private func makeEntry(
        _ name: String, mode: OpenMode? = nil, browser: String? = nil
    ) throws -> URL {
        let fileURL = root.appendingPathComponent(name)
        try WeblocFile(
            url: URL(string: "https://example.com")!,
            openMode: mode,
            browserBundleID: browser
        ).write(to: fileURL)
        return fileURL
    }

    func testNormalEntryUsesTheSystemDefault() throws {
        let model = try makeModel()
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc"), in: root)

        XCTAssertEqual(plan.resolvedMode, .normal)
        XCTAssertEqual(plan.asResolved, .success(.openWithSystemDefault(plan.target)))
    }

    func testOptionInvertsANormalEntryIntoTheConfiguredPrivateBrowser() throws {
        let model = try makeModel()
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc"), in: root)

        XCTAssertEqual(plan.inverted, .success(.openApplication(
            bundleID: "org.mozilla.firefox",
            arguments: ["-private-window", "https://example.com"])))
    }

    func testOptionInvertsAPrivateEntryBackToTheNormalBrowser() throws {
        let model = try makeModel(normal: "com.apple.Safari")
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc", mode: .privateWindow), in: root)

        XCTAssertEqual(plan.resolvedMode, .privateWindow)
        XCTAssertEqual(plan.inverted, .success(.openApplication(
            bundleID: "com.apple.Safari", arguments: ["https://example.com"])))
    }

    /// An entry pinned to Safari cannot be inverted into a private window using
    /// Safari — the model has to fall back to the configured private browser
    /// rather than produce an impossible plan or a normal open.
    func testInvertingASafariPinnedEntryFallsBackToThePrivateBrowser() throws {
        let model = try makeModel()
        let plan = try model.plan(
            forEntryAt: makeEntry("A.webloc", browser: "com.apple.Safari"), in: root)

        XCTAssertEqual(plan.asResolved, .success(.openApplication(
            bundleID: "com.apple.Safari", arguments: ["https://example.com"])))
        XCTAssertEqual(plan.inverted, .success(.openApplication(
            bundleID: "org.mozilla.firefox",
            arguments: ["-private-window", "https://example.com"])))
    }

    func testInversionIsBlockedWhenNoPrivateBrowserIsConfigured() throws {
        let model = try makeModel(private: "")
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc"), in: root)

        XCTAssertEqual(plan.inverted, .failure(.noPrivateBrowserConfigured))
    }

    func testFolderDefaultsFlowIntoThePlan() throws {
        let shelf = FakeShelf(defaultsByPath: [
            root.lastPathComponent: FolderDefaults(openMode: .privateWindow, browserBundleID: nil),
        ])
        let model = try makeModel(shelf: shelf)
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc"), in: root)

        XCTAssertEqual(plan.resolvedMode, .privateWindow)
        XCTAssertEqual(plan.asResolved, .success(.openApplication(
            bundleID: "org.mozilla.firefox",
            arguments: ["-private-window", "https://example.com"])))
    }

    func testUnreadableEntryThrows() throws {
        let model = try makeModel()
        let fileURL = root.appendingPathComponent("Broken.webloc")
        try "not a plist".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try model.plan(forEntryAt: fileURL, in: root))
    }

    func testRunHandsTheActionToTheLauncher() throws {
        let launcher = SpyLauncher()
        let model = try makeModel(launcher: launcher)
        let plan = try model.plan(forEntryAt: makeEntry("A.webloc", mode: .privateWindow), in: root)

        guard case .success(let action) = plan.asResolved else { return XCTFail("expected success") }
        model.run(action)

        XCTAssertEqual(launcher.actions, [action])
    }

    func testSetRootPersistsToTheConfigFile() throws {
        let model = try makeModel()
        let newRoot = root.appendingPathComponent("elsewhere")
        try model.setRoot(newRoot)

        XCTAssertEqual(AppConfig.read(contentsOf: configURL).rootPath, newRoot.path)
    }

    func testReloadConfigPicksUpHandEdits() throws {
        let model = try makeModel(normal: "default")
        XCTAssertEqual(model.config.normalBrowser, .systemDefault)

        try """
        [browser]
        normal = "com.google.Chrome"
        """.write(to: configURL, atomically: true, encoding: .utf8)
        model.reloadConfig()

        XCTAssertEqual(model.config.normalBrowser, .bundleID("com.google.Chrome"))
    }
}

@MainActor
final class BrowserSelectionPersistenceTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        configURL = root.appendingPathComponent("config.toml")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(installed: Set<String>) -> AppModel {
        AppModel(
            configURL: configURL,
            shelf: FakeShelf(),
            inventory: FakeInventory(installed: installed),
            launcher: SpyLauncher())
    }

    func testSettingThePrivateBrowserPersists() throws {
        let model = makeModel(installed: ["org.mozilla.firefox"])
        try model.setPrivateBrowser("org.mozilla.firefox")

        XCTAssertEqual(AppConfig.read(contentsOf: configURL).privateBrowser, "org.mozilla.firefox")
    }

    func testClearingThePrivateBrowserPersistsAsUnset() throws {
        let model = makeModel(installed: ["org.mozilla.firefox"])
        try model.setPrivateBrowser("org.mozilla.firefox")
        try model.setPrivateBrowser(nil)

        XCTAssertNil(AppConfig.read(contentsOf: configURL).privateBrowser)
    }

    func testSettingTheNormalBrowserPersists() throws {
        let model = makeModel(installed: ["com.apple.Safari"])
        try model.setNormalBrowser(.bundleID("com.apple.Safari"))

        XCTAssertEqual(
            AppConfig.read(contentsOf: configURL).normalBrowser, .bundleID("com.apple.Safari"))
    }

    /// The prompt appears only when choosing a browser would actually help.
    func testNeedsChoiceOnlyWhenACapableBrowserExists() throws {
        let capable = makeModel(installed: ["org.mozilla.firefox", "com.apple.Safari"])
        XCTAssertTrue(capable.needsPrivateBrowserChoice)

        let safariOnly = makeModel(installed: ["com.apple.Safari"])
        XCTAssertFalse(safariOnly.needsPrivateBrowserChoice)

        try capable.setPrivateBrowser("org.mozilla.firefox")
        XCTAssertFalse(capable.needsPrivateBrowserChoice)
    }
}

@MainActor
final class UpdateEntryTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let configURL = root.appendingPathComponent("config.toml")
        try "[shelf]\nroot = \(MiniTOML.quote(root.path))"
            .write(to: configURL, atomically: true, encoding: .utf8)
        model = AppModel(configURL: configURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeEntry() throws -> URL {
        try model.addEntry(url: URL(string: "https://example.com")!, name: "Entry", in: root)
    }

    func testChangesTheURLWithoutTouchingTheRest() throws {
        let fileURL = try makeEntry()
        try model.updateEntry(at: fileURL, openMode: .some(.privateWindow))
        try model.updateEntry(at: fileURL, url: URL(string: "https://example.org")!)

        let reloaded = try model.entry(at: fileURL)
        XCTAssertEqual(reloaded.url.absoluteString, "https://example.org")
        XCTAssertEqual(reloaded.openMode, .privateWindow)
    }

    /// Clearing a setting is an edit, not an omission — hence the double optional.
    func testClearingAnOverrideRemovesTheKey() throws {
        let fileURL = try makeEntry()
        try model.updateEntry(at: fileURL, browserBundleID: .some("com.google.Chrome"))
        try model.updateEntry(at: fileURL, browserBundleID: .some(nil))

        let reloaded = try model.entry(at: fileURL)
        XCTAssertNil(reloaded.browserBundleID)
        XCTAssertEqual(reloaded.foreignKeys, [])
    }

    func testOmittedArgumentsLeaveTheEntryAlone() throws {
        let fileURL = try makeEntry()
        try model.updateEntry(at: fileURL, openMode: .some(.privateWindow))
        try model.updateEntry(at: fileURL)

        XCTAssertEqual(try model.entry(at: fileURL).openMode, .privateWindow)
    }

    func testEditingPreservesAnotherToolsKeys() throws {
        let fileURL = root.appendingPathComponent("Foreign.webloc")
        try Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        <key>URL</key><string>https://example.com</string>
        <key>com.example.other</key><string>keep me</string>
        </dict>
        </plist>
        """.utf8).write(to: fileURL)

        try model.updateEntry(at: fileURL, openMode: .some(.privateWindow))

        XCTAssertEqual(try model.entry(at: fileURL).foreignKeys, ["com.example.other"])
    }
}
