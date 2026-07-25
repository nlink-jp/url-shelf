import XCTest
@testable import URLShelf

final class EntryNamingTests: XCTestCase {
    func testUsesThePreferredNameWhenGiven() {
        XCTAssertEqual(
            EntryNaming.filename(for: URL(string: "https://example.com")!, preferred: "My Wiki"),
            "My Wiki")
    }

    func testFallsBackToTheHostWithoutWWW() {
        XCTAssertEqual(
            EntryNaming.filename(for: URL(string: "https://www.example.com/a/b")!, preferred: nil),
            "example.com")
    }

    func testBlankPreferredNameIsIgnored() {
        XCTAssertEqual(
            EntryNaming.filename(for: URL(string: "https://example.com")!, preferred: "   "),
            "example.com")
    }

    func testReplacesPathSeparators() {
        // The filesystem would silently reinterpret these.
        XCTAssertEqual(EntryNaming.sanitize("a/b:c"), "a-b-c")
    }

    func testStripsLeadingDotSoTheEntryIsNotHidden() {
        XCTAssertEqual(EntryNaming.sanitize(".hidden"), "hidden")
    }

    func testEmptyNameBecomesUntitled() {
        XCTAssertEqual(EntryNaming.sanitize("   "), "Untitled")
        XCTAssertEqual(EntryNaming.sanitize("/"), "Untitled")
    }

    func testUniqueURLAppendsACounterInsteadOfOverwriting() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let first = EntryNaming.uniqueURL(in: folder, base: "Site", extension: "webloc")
        XCTAssertEqual(first.lastPathComponent, "Site.webloc")
        try Data().write(to: first)

        let second = EntryNaming.uniqueURL(in: folder, base: "Site", extension: "webloc")
        XCTAssertEqual(second.lastPathComponent, "Site 2.webloc")
    }
}

@MainActor
final class DroppedURLTests: XCTestCase {
    func testAcceptsWebURLs() {
        XCTAssertEqual(
            URLDropView.webURL(fromText: "  https://example.com/a  "),
            URL(string: "https://example.com/a"))
    }

    func testRejectsBareHostnames() {
        // Guessing a scheme for a dropped fragment would open something the user
        // did not point at.
        XCTAssertNil(URLDropView.webURL(fromText: "example.com"))
    }

    func testRejectsNonBrowsableSchemes() {
        XCTAssertNil(URLDropView.webURL(fromText: "javascript:alert(1)"))
        XCTAssertNil(URLDropView.webURL(fromText: "mailto:someone@example.com"))
    }

    func testRejectsPlainText() {
        XCTAssertNil(URLDropView.webURL(fromText: "just some words"))
    }
}

@MainActor
final class AddEntryTests: XCTestCase {
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

    private func makeModel(inbox: String = "") throws -> AppModel {
        let shelfRoot = root.appendingPathComponent("shelf")
        try FileManager.default.createDirectory(at: shelfRoot, withIntermediateDirectories: true)
        try """
        [shelf]
        root  = \(MiniTOML.quote(shelfRoot.path))
        inbox = \(MiniTOML.quote(inbox))
        """.write(to: configURL, atomically: true, encoding: .utf8)
        return AppModel(configURL: configURL)
    }

    func testAddsAReadableEntry() throws {
        let model = try makeModel()
        let fileURL = try model.addEntry(
            url: URL(string: "https://example.com")!,
            name: "Example",
            in: model.rootURL!,
            openMode: .privateWindow)

        XCTAssertEqual(fileURL.lastPathComponent, "Example.webloc")
        let reloaded = try WeblocFile.read(contentsOf: fileURL)
        XCTAssertEqual(reloaded.url.absoluteString, "https://example.com")
        XCTAssertEqual(reloaded.openMode, .privateWindow)
    }

    func testAddingTwiceDoesNotOverwrite() throws {
        let model = try makeModel()
        let first = try model.addEntry(url: URL(string: "https://example.com")!, in: model.rootURL!)
        let second = try model.addEntry(url: URL(string: "https://example.com")!, in: model.rootURL!)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
    }

    func testInboxDefaultsToTheRoot() throws {
        let model = try makeModel()
        XCTAssertEqual(try model.inboxURL(), model.rootURL)
    }

    func testInboxFolderIsCreatedOnDemand() throws {
        let model = try makeModel(inbox: "Inbox")
        let inbox = try model.inboxURL()

        XCTAssertEqual(inbox.lastPathComponent, "Inbox")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inbox.path))
    }

    func testInboxFailsWithoutARoot() throws {
        try "".write(to: configURL, atomically: true, encoding: .utf8)
        let model = AppModel(configURL: configURL)

        XCTAssertThrowsError(try model.inboxURL()) { error in
            XCTAssertEqual(error as? ShelfError, .noRootConfigured)
        }
    }

    func testFolderPathsAreRelativeAndIncludeTheRoot() throws {
        let model = try makeModel()
        let research = model.rootURL!.appendingPathComponent("research/malware")
        try FileManager.default.createDirectory(at: research, withIntermediateDirectories: true)

        XCTAssertEqual(model.folderPaths(), ["", "research", "research/malware"])
        // Compared by path: URL(fileURLWithPath:) appends a trailing slash for
        // directories that exist, so URL equality is not stable here.
        XCTAssertEqual(model.url(forFolderPath: "research/malware")?.path, research.path)
    }
}
