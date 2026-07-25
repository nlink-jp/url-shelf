import XCTest
@testable import URLShelf

final class RenamedFilenameTests: XCTestCase {
    func testKeepsTheOrderingPrefix() {
        // Renaming must not silently move an entry in the menu.
        XCTAssertEqual(
            DisplayName.renamedFilename("01_Wiki.webloc", to: "Docs"), "01_Docs.webloc")
        XCTAssertEqual(
            DisplayName.renamedFilename("10 - Wiki.webloc", to: "Docs"), "10 - Docs.webloc")
    }

    func testKeepsTheExtension() {
        XCTAssertEqual(DisplayName.renamedFilename("Wiki.webloc", to: "Docs"), "Docs.webloc")
    }

    func testFoldersHaveNoExtension() {
        XCTAssertEqual(DisplayName.renamedFilename("02_Work", to: "Research"), "02_Research")
    }

    func testSanitizesTheNewName() {
        XCTAssertEqual(
            DisplayName.renamedFilename("Wiki.webloc", to: "a/b"), "a-b.webloc")
    }

    func testDoesNotTreatAYearAsAPrefix() {
        XCTAssertEqual(
            DisplayName.renamedFilename("2026-07-26 notes.webloc", to: "Notes"), "Notes.webloc")
    }

    func testOrderPrefixMatchesTheStrippedName() {
        for stem in ["01_Wiki", "10 - Docs", "Wiki", "2026-07-26 notes", "007", "3Dプリンタ"] {
            XCTAssertEqual(
                DisplayName.orderPrefix(of: stem) + DisplayName.strippingOrderPrefix(stem),
                stem, stem)
        }
    }
}

final class ShelfEditorTests: XCTestCase {
    private var root: URL!
    private let editor = FileSystemShelfEditor()
    private let shelf = FileSystemShelf()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeEntry(_ path: String) throws -> URL {
        let fileURL = root.appendingPathComponent(path)
        try WeblocFile(url: URL(string: "https://example.com")!).write(to: fileURL)
        return fileURL
    }

    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func testCreateFolder() throws {
        let url = try editor.createFolder(named: "Research", in: root)

        XCTAssertEqual(url.lastPathComponent, "Research")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testCreateFolderDoesNotCollide() throws {
        let first = try editor.createFolder(named: "Research", in: root)
        let second = try editor.createFolder(named: "Research", in: root)

        XCTAssertEqual(second.lastPathComponent, "Research 2")
        XCTAssertTrue(exists(first))
    }

    func testRenameKeepsThePrefixAndMovesTheFile() throws {
        let original = try makeEntry("01_Wiki.webloc")
        let renamed = try editor.rename(original, toDisplayName: "Docs")

        XCTAssertEqual(renamed.lastPathComponent, "01_Docs.webloc")
        XCTAssertFalse(exists(original))
        XCTAssertEqual(try WeblocFile.read(contentsOf: renamed).url.absoluteString,
                       "https://example.com")
    }

    func testRenameToTheSameNameIsANoOp() throws {
        let original = try makeEntry("Wiki.webloc")
        XCTAssertEqual(try editor.rename(original, toDisplayName: "Wiki"), original)
        XCTAssertTrue(exists(original))
    }

    func testRenameOntoAnExistingNameDoesNotOverwrite() throws {
        let taken = try makeEntry("Docs.webloc")
        let original = try makeEntry("Wiki.webloc")

        let renamed = try editor.rename(original, toDisplayName: "Docs")
        XCTAssertEqual(renamed.lastPathComponent, "Docs 2.webloc")
        XCTAssertTrue(exists(taken))
    }

    func testMoveIntoAFolder() throws {
        let folder = try editor.createFolder(named: "Research", in: root)
        let entry = try makeEntry("Wiki.webloc")

        let moved = try editor.move(entry, to: folder)
        XCTAssertEqual(moved.deletingLastPathComponent().lastPathComponent, "Research")
        XCTAssertFalse(exists(entry))
    }

    func testMoveToTheCurrentFolderIsANoOp() throws {
        let entry = try makeEntry("Wiki.webloc")
        XCTAssertEqual(try editor.move(entry, to: root), entry)
        XCTAssertTrue(exists(entry))
    }

    func testMoveRefusesToPutAFolderInsideItself() throws {
        let parent = try editor.createFolder(named: "Parent", in: root)
        let child = try editor.createFolder(named: "Child", in: parent)

        XCTAssertThrowsError(try editor.move(parent, to: child)) { error in
            XCTAssertEqual(error as? ShelfEditError, .folderIntoItself)
        }
        XCTAssertThrowsError(try editor.move(parent, to: parent)) { error in
            XCTAssertEqual(error as? ShelfEditError, .folderIntoItself)
        }
    }

    func testMoveDoesNotOverwriteANameAlreadyThere() throws {
        let folder = try editor.createFolder(named: "Research", in: root)
        let existing = try makeEntry("Research/Wiki.webloc")
        let entry = try makeEntry("Wiki.webloc")

        let moved = try editor.move(entry, to: folder)
        XCTAssertEqual(moved.lastPathComponent, "Wiki 2.webloc")
        XCTAssertTrue(exists(existing))
    }

    /// Deleting must be recoverable: entries are the user's data, not a cache.
    func testTrashRemovesTheFileFromTheShelfButNotFromDisk() throws {
        let entry = try makeEntry("Wiki.webloc")
        try editor.trash(entry)

        XCTAssertFalse(exists(entry))
        XCTAssertEqual(try shelf.children(of: root).count, 0)
    }
}

final class ShelfTreeTests: XCTestCase {
    private var root: URL!
    private let shelf = FileSystemShelf()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBuildsTheWholeTree() throws {
        let research = root.appendingPathComponent("research")
        try FileManager.default.createDirectory(at: research, withIntermediateDirectories: true)
        try WeblocFile(url: URL(string: "https://example.com")!)
            .write(to: research.appendingPathComponent("IANA.webloc"))
        try WeblocFile(url: URL(string: "https://example.com")!)
            .write(to: root.appendingPathComponent("Wiki.webloc"))

        let tree = shelf.tree(at: root, name: "Shelf")
        XCTAssertEqual(tree.name, "Shelf")
        XCTAssertEqual(tree.children?.map(\.name), ["research", "Wiki"])

        let folder = tree.children?.first
        XCTAssertEqual(folder?.isFolder, true)
        XCTAssertEqual(folder?.children?.map(\.name), ["IANA"])
        XCTAssertNil(tree.children?.last?.children, "entries are leaves")
    }

    func testEmptyFolderHasEmptyChildrenNotNil() throws {
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        XCTAssertEqual(shelf.tree(at: root).children?.first?.children, [])
    }

    /// A symlink can point back up the tree; the walk must terminate regardless.
    func testDepthIsCapped() throws {
        var current = root!
        for index in 0..<5 {
            current = current.appendingPathComponent("level\(index)")
            try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        }

        var node = shelf.tree(at: root, maxDepth: 3)
        var depth = 0
        while let child = node.children?.first {
            node = child
            depth += 1
        }
        XCTAssertEqual(depth, 3)
    }
}
