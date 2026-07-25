import XCTest
@testable import URLShelf

final class ShelfStoreTests: XCTestCase {
    private var root: URL!
    private let shelf = FileSystemShelf()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func makeEntry(_ path: String, url: String = "https://example.com") throws -> URL {
        let fileURL = root.appendingPathComponent(path)
        try WeblocFile(url: URL(string: url)!).write(to: fileURL)
        return fileURL
    }

    private func makeDefaults(_ path: String, _ defaults: FolderDefaults) throws {
        let fileURL = root.appendingPathComponent(path)
            .appendingPathComponent(FolderDefaults.filename)
        try defaults.serialized().write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func testListsFoldersAndEntries() throws {
        try makeFolder("work")
        try makeEntry("Expenses.webloc")

        XCTAssertEqual(try shelf.children(of: root).map(\.name), ["Expenses", "work"])
    }

    func testIgnoresNonWeblocFiles() throws {
        try makeEntry("Keep.webloc")
        try "notes".write(
            to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)

        XCTAssertEqual(try shelf.children(of: root).map(\.name), ["Keep"])
    }

    func testIgnoresDotfilesIncludingFolderDefaults() throws {
        try makeDefaults("", FolderDefaults(openMode: .privateWindow, browserBundleID: nil))
        try makeEntry("Visible.webloc")

        XCTAssertEqual(try shelf.children(of: root).map(\.name), ["Visible"])
    }

    func testSortsByFilenameSoOrderingPrefixesWork() throws {
        try makeEntry("10_Ten.webloc")
        try makeEntry("2_Two.webloc")
        try makeEntry("1_One.webloc")

        // Natural ordering: 1, 2, 10 — not lexicographic 1, 10, 2.
        XCTAssertEqual(try shelf.children(of: root).map(\.name), ["One", "Two", "Ten"])
    }

    func testFoldersAndEntriesInterleaveByPrefix() throws {
        try makeFolder("2_Research")
        try makeEntry("1_Wiki.webloc")
        try makeEntry("3_Expenses.webloc")

        XCTAssertEqual(
            try shelf.children(of: root).map(\.name), ["Wiki", "Research", "Expenses"])
    }

    func testChildrenIsOneLevelOnly() throws {
        try makeFolder("work")
        try makeEntry("work/Nested.webloc")

        let top = try shelf.children(of: root)
        XCTAssertEqual(top.count, 1)
        guard case .folder(_, let folderURL) = top[0] else { return XCTFail("expected a folder") }
        XCTAssertEqual(try shelf.children(of: folderURL).map(\.name), ["Nested"])
    }

    func testDefaultsAreEmptyWhenAbsent() {
        XCTAssertTrue(shelf.defaults(at: root).isEmpty)
    }

    func testDefaultsChainIsRootFirst() throws {
        try makeFolder("research/malware")
        try makeDefaults("", FolderDefaults(openMode: .normal, browserBundleID: nil))
        try makeDefaults("research", FolderDefaults(openMode: .privateWindow, browserBundleID: nil))

        let chain = shelf.defaultsChain(
            from: root, to: root.appendingPathComponent("research/malware"))
        XCTAssertEqual(chain.count, 3)
        XCTAssertEqual(chain[0].openMode, .normal)
        XCTAssertEqual(chain[1].openMode, .privateWindow)
        XCTAssertTrue(chain[2].isEmpty)

        // The nearest non-empty ancestor decides: research/ makes it private.
        let plan = MetadataResolver.resolve(
            entryMode: nil, entryBrowser: nil, folderChain: chain,
            config: AppConfig(
                rootPath: nil, inbox: "", normalBrowser: .systemDefault,
                privateBrowser: "org.mozilla.firefox"))
        XCTAssertEqual(
            plan, OpenPlan(mode: .privateWindow, browser: .bundleID("org.mozilla.firefox")))
    }

    func testDefaultsChainForFolderOutsideRoot() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(shelf.defaultsChain(from: root, to: outside).count, 1)
    }

    func testMissingFolderThrows() {
        XCTAssertThrowsError(try shelf.children(of: root.appendingPathComponent("nope")))
    }
}
