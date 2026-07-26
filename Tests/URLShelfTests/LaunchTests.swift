import XCTest
@testable import URLShelf

private let example = URL(string: "https://example.com")!

final class MetadataResolverTests: XCTestCase {
    private let config = AppConfig(
        rootPath: nil,
        inbox: "",
        sort: .default,
        normalBrowser: .bundleID("com.apple.Safari"),
        privateBrowser: "org.mozilla.firefox")

    func testDefaultsToNormalWithTheConfiguredNormalBrowser() {
        let plan = MetadataResolver.resolve(
            entryMode: nil, entryBrowser: nil, folderChain: [], config: config)
        XCTAssertEqual(plan, OpenPlan(mode: .normal, browser: .bundleID("com.apple.Safari")))
    }

    func testFolderDefaultApplies() {
        let plan = MetadataResolver.resolve(
            entryMode: nil,
            entryBrowser: nil,
            folderChain: [.empty, FolderDefaults(openMode: .privateWindow, browserBundleID: nil)],
            config: config)
        XCTAssertEqual(
            plan, OpenPlan(mode: .privateWindow, browser: .bundleID("org.mozilla.firefox")))
    }

    func testNearestFolderWins() {
        let plan = MetadataResolver.resolve(
            entryMode: nil,
            entryBrowser: nil,
            folderChain: [
                FolderDefaults(openMode: .privateWindow, browserBundleID: "com.google.Chrome"),
                FolderDefaults(openMode: .normal, browserBundleID: "com.apple.Safari"),
            ],
            config: config)
        XCTAssertEqual(plan, OpenPlan(mode: .normal, browser: .bundleID("com.apple.Safari")))
    }

    func testEntryOverridesFolder() {
        let plan = MetadataResolver.resolve(
            entryMode: .normal,
            entryBrowser: "com.google.Chrome",
            folderChain: [FolderDefaults(openMode: .privateWindow, browserBundleID: "org.mozilla.firefox")],
            config: config)
        XCTAssertEqual(plan, OpenPlan(mode: .normal, browser: .bundleID("com.google.Chrome")))
    }

    func testPrivateWithNoPrivateBrowserConfiguredDoesNotBorrowTheNormalOne() {
        var bare = config
        bare.privateBrowser = nil
        let plan = MetadataResolver.resolve(
            entryMode: .privateWindow, entryBrowser: nil, folderChain: [], config: bare)
        XCTAssertEqual(plan, OpenPlan(mode: .privateWindow, browser: .systemDefault))
        // …and that combination is refused downstream rather than opened normally.
        XCTAssertEqual(
            LaunchPlanner.action(for: example, plan: plan),
            .failure(.noPrivateBrowserConfigured))
    }

    func testResolvesFromAWeblocFile() {
        var entry = WeblocFile(url: example)
        entry.openMode = .privateWindow
        let plan = MetadataResolver.resolve(entry: entry, folderChain: [], config: config)
        XCTAssertEqual(
            plan, OpenPlan(mode: .privateWindow, browser: .bundleID("org.mozilla.firefox")))
    }
}

final class LaunchPlannerTests: XCTestCase {
    func testNormalWithSystemDefaultGoesThroughLaunchServices() {
        let action = LaunchPlanner.action(
            for: example, plan: OpenPlan(mode: .normal, browser: .systemDefault))
        XCTAssertEqual(action, .success(.openWithSystemDefault(example)))
    }

    func testNormalWithExplicitBrowserPassesOnlyTheURL() {
        let action = LaunchPlanner.action(
            for: example,
            plan: OpenPlan(mode: .normal, browser: .bundleID("com.google.Chrome")))
        XCTAssertEqual(action, .success(.openApplication(
            bundleID: "com.google.Chrome", arguments: ["https://example.com"])))
    }

    /// Regression guard for the spike's central finding: Firefox takes the
    /// Mozilla-style *single* dash. The GNU-style `--private-window` is accepted
    /// and silently ignored, opening the URL in a normal window — the exact
    /// accident this app exists to prevent, and one that raises no error.
    func testFirefoxUsesSingleDashPrivateWindow() {
        let action = LaunchPlanner.action(
            for: example,
            plan: OpenPlan(mode: .privateWindow, browser: .bundleID("org.mozilla.firefox")))
        XCTAssertEqual(action, .success(.openApplication(
            bundleID: "org.mozilla.firefox",
            arguments: ["-private-window", "https://example.com"])))
    }

    func testChromiumBrowsersUseTheirOwnFlags() {
        let cases = [
            ("com.google.Chrome", "--incognito"),
            ("com.microsoft.edgemac", "--inprivate"),
            ("com.brave.Browser", "--incognito"),
        ]
        for (bundleID, flag) in cases {
            let action = LaunchPlanner.action(
                for: example,
                plan: OpenPlan(mode: .privateWindow, browser: .bundleID(bundleID)))
            XCTAssertEqual(action, .success(.openApplication(
                bundleID: bundleID, arguments: [flag, "https://example.com"])), bundleID)
        }
    }

    func testSafariCannotOpenPrivately() {
        let action = LaunchPlanner.action(
            for: example,
            plan: OpenPlan(mode: .privateWindow, browser: .bundleID("com.apple.Safari")))
        XCTAssertEqual(action, .failure(.privateNotSupported(bundleID: "com.apple.Safari")))
    }

    func testSafariIsStillFineForNormalOpens() {
        let action = LaunchPlanner.action(
            for: example, plan: OpenPlan(mode: .normal, browser: .bundleID("com.apple.Safari")))
        XCTAssertEqual(action, .success(.openApplication(
            bundleID: "com.apple.Safari", arguments: ["https://example.com"])))
    }

    func testUnknownBrowserIsRefusedForPrivate() {
        let action = LaunchPlanner.action(
            for: example, plan: OpenPlan(mode: .privateWindow, browser: .bundleID("com.example.Nope")))
        XCTAssertEqual(action, .failure(.unknownBrowser(bundleID: "com.example.Nope")))
    }

    func testNoPlanEverDowngradesPrivateToNormal() {
        // Whatever the configuration, a private plan either produces a launch
        // carrying a private flag, or fails. It never opens a plain URL.
        for capability in BrowserCatalog.all {
            let plan = OpenPlan(mode: .privateWindow, browser: .bundleID(capability.bundleID))
            switch LaunchPlanner.action(for: example, plan: plan) {
            case .success(.openApplication(_, let arguments)):
                XCTAssertEqual(arguments.first, capability.privateFlag, capability.bundleID)
            case .success(.openWithSystemDefault):
                XCTFail("private plan produced a default-browser open: \(capability.bundleID)")
            case .failure:
                XCTAssertNil(capability.privateFlag, capability.bundleID)
            }
        }
    }

    func testInvertedFlipsBothWays() {
        XCTAssertEqual(LaunchPlanner.inverted(.normal), .privateWindow)
        XCTAssertEqual(LaunchPlanner.inverted(.privateWindow), .normal)
    }
}

private struct FakeInventory: BrowserInventory {
    let installed: Set<String>
    func isInstalled(bundleID: String) -> Bool { installed.contains(bundleID) }
}

final class BrowserCatalogTests: XCTestCase {
    func testListsOnlyInstalledBrowsers() {
        let inventory = FakeInventory(installed: ["com.apple.Safari", "com.google.Chrome"])
        XCTAssertEqual(
            inventory.installedBrowsers().map(\.bundleID).sorted(),
            ["com.apple.Safari", "com.google.Chrome"])
    }

    func testPrivateCapableExcludesSafari() {
        let inventory = FakeInventory(installed: ["com.apple.Safari", "com.google.Chrome"])
        XCTAssertEqual(inventory.privateCapableBrowsers().map(\.bundleID), ["com.google.Chrome"])
    }

    func testSafariOnlyMachineHasNoPrivateOption() {
        let inventory = FakeInventory(installed: ["com.apple.Safari"])
        XCTAssertTrue(inventory.privateCapableBrowsers().isEmpty)
    }

    func testBundleIDsAreUnique() {
        let ids = BrowserCatalog.all.map(\.bundleID)
        XCTAssertEqual(Set(ids).count, ids.count)
    }
}
