import XCTest
@testable import URLShelf

final class ShelfOrderingTests: XCTestCase {
    func testNumbersWithGapsSoEntriesCanBeInsertedByHand() throws {
        let renames = try ShelfOrdering.renames(for: ["B.webloc", "A.webloc"])

        XCTAssertEqual(renames.map(\.to), ["010_B.webloc", "020_A.webloc"])
    }

    func testKeepsTheExtensionAndDropsTheOldPrefix() throws {
        let renames = try ShelfOrdering.renames(for: ["99_Old.webloc"])

        XCTAssertEqual(renames.first?.to, "010_Old.webloc")
    }

    func testFoldersHaveNoExtension() throws {
        let renames = try ShelfOrdering.renames(for: ["Research"])

        XCTAssertEqual(renames.first?.to, "010_Research")
    }

    func testAlreadyCorrectNamesAreNotRenamed() throws {
        let renames = try ShelfOrdering.renames(for: ["010_A.webloc", "020_B.webloc"])

        XCTAssertTrue(renames.isEmpty)
    }

    /// A three-digit prefix is the cap, because a four-digit run reads as a year.
    func testFallsBackToAStepOfOneWhenGapsWouldOverflow() {
        XCTAssertEqual(ShelfOrdering.step(forCount: 99), 10)
        XCTAssertEqual(ShelfOrdering.step(forCount: 100), 1)
    }

    func testNumbersStayThreeDigitsAtTheLimit() throws {
        let names = (0..<999).map { "Item\($0).webloc" }
        let renames = try ShelfOrdering.renames(for: names)

        XCTAssertEqual(renames.last?.to, "999_Item998.webloc")
        XCTAssertTrue(renames.allSatisfy { $0.to.prefix(3).allSatisfy(\.isNumber) })
    }

    func testRefusesAFolderTooLargeToNumber() {
        let names = (0...999).map { "Item\($0).webloc" }

        XCTAssertThrowsError(try ShelfOrdering.renames(for: names)) { error in
            XCTAssertEqual(error as? ShelfOrderingError, .folderTooLarge(count: 1000))
        }
    }

    // MARK: - Reordering

    private func urls(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/shelf/\($0)") }
    }

    func testMovesAnItemBeforeAnother() {
        let current = urls(["A", "B", "C"])
        let result = ShelfOrdering.reordered(
            current, moving: current[2], to: .before, relativeTo: current[0])

        XCTAssertEqual(result.map(\.lastPathComponent), ["C", "A", "B"])
    }

    func testMovesAnItemAfterAnother() {
        let current = urls(["A", "B", "C"])
        let result = ShelfOrdering.reordered(
            current, moving: current[0], to: .after, relativeTo: current[2])

        XCTAssertEqual(result.map(\.lastPathComponent), ["B", "C", "A"])
    }

    func testInsertsAnItemComingFromAnotherFolder() {
        let current = urls(["A", "B"])
        let incoming = URL(fileURLWithPath: "/shelf/research/New")
        let result = ShelfOrdering.reordered(
            current, moving: incoming, to: .after, relativeTo: current[0])

        XCTAssertEqual(result.map(\.lastPathComponent), ["A", "New", "B"])
    }

    func testUnknownTargetLeavesTheOrderAlone() {
        let current = urls(["A", "B"])
        let result = ShelfOrdering.reordered(
            current, moving: current[0], to: .after,
            relativeTo: URL(fileURLWithPath: "/shelf/gone"))

        XCTAssertEqual(result, current)
    }
}

final class ReorderExecutionTests: XCTestCase {
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
    private func makeEntry(_ name: String) throws -> URL {
        let fileURL = root.appendingPathComponent(name)
        try WeblocFile(url: URL(string: "https://example.com/\(name)")!).write(to: fileURL)
        return fileURL
    }

    private func names() throws -> [String] {
        try shelf.children(of: root).map(\.url.lastPathComponent)
    }

    func testRenumbersTheFolderIntoTheGivenOrder() throws {
        let a = try makeEntry("Alpha.webloc")
        let b = try makeEntry("Beta.webloc")

        try editor.reorder(in: root, to: [b, a])

        XCTAssertEqual(try names(), ["010_Beta.webloc", "020_Alpha.webloc"])
    }

    /// The case that breaks a naive one-pass rename: the two files swap names.
    func testSwappingTwoNamesDoesNotLoseAFile() throws {
        let a = try makeEntry("010_Alpha.webloc")
        let b = try makeEntry("020_Beta.webloc")

        try editor.reorder(in: root, to: [b, a])

        XCTAssertEqual(try names(), ["010_Beta.webloc", "020_Alpha.webloc"])
        let first = try WeblocFile.read(contentsOf: root.appendingPathComponent("010_Beta.webloc"))
        XCTAssertEqual(first.url.absoluteString, "https://example.com/020_Beta.webloc")
    }

    func testLeavesNoTemporaryFilesBehind() throws {
        let a = try makeEntry("Alpha.webloc")
        let b = try makeEntry("Beta.webloc")
        try editor.reorder(in: root, to: [b, a])

        let all = try FileManager.default.contentsOfDirectory(atPath: root.path)
        XCTAssertTrue(all.allSatisfy { !$0.hasPrefix(".url-shelf-reorder") }, "\(all)")
    }

    func testReturnsTheNewURLsInTheSameOrder() throws {
        let a = try makeEntry("Alpha.webloc")
        let b = try makeEntry("Beta.webloc")

        let result = try editor.reorder(in: root, to: [b, a])

        XCTAssertEqual(
            result.map(\.lastPathComponent), ["010_Beta.webloc", "020_Alpha.webloc"])
    }

    func testFoldersAreRenumberedToo() throws {
        let folder = try editor.createFolder(named: "Research", in: root)
        let entry = try makeEntry("Alpha.webloc")

        try editor.reorder(in: root, to: [entry, folder])

        XCTAssertEqual(try names(), ["010_Alpha.webloc", "020_Research"])
    }

    func testAlreadyOrderedFolderIsUntouched() throws {
        let a = try makeEntry("010_Alpha.webloc")
        let b = try makeEntry("020_Beta.webloc")
        let before = try FileManager.default.attributesOfItem(atPath: a.path)[.creationDate] as? Date

        try editor.reorder(in: root, to: [a, b])

        let after = try FileManager.default.attributesOfItem(atPath: a.path)[.creationDate] as? Date
        XCTAssertEqual(before, after)
        XCTAssertEqual(try names(), ["010_Alpha.webloc", "020_Beta.webloc"])
    }
}

@MainActor
final class DropIntegrationTests: XCTestCase {
    private var root: URL!
    private var configURL: URL!
    private var model: AppModel!
    private let shelf = FileSystemShelf()

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        root = base.appendingPathComponent("shelf")
        configURL = base.appendingPathComponent("config.toml")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "[shelf]\nroot = \(MiniTOML.quote(root.path))"
            .write(to: configURL, atomically: true, encoding: .utf8)
        model = AppModel(configURL: configURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    @discardableResult
    private func makeEntry(_ name: String, in folder: URL? = nil) throws -> URL {
        let fileURL = (folder ?? root).appendingPathComponent(name)
        try WeblocFile(url: URL(string: "https://example.com")!).write(to: fileURL)
        return fileURL
    }

    private func names(in folder: URL? = nil) throws -> [String] {
        try shelf.children(of: folder ?? root).map(\.url.lastPathComponent)
    }

    func testDroppingNextToASiblingReordersTheFolder() throws {
        let a = try makeEntry("Alpha.webloc")
        let c = try makeEntry("Charlie.webloc")

        try model.drop(c, .before, relativeTo: a)

        XCTAssertEqual(try names(), ["010_Charlie.webloc", "020_Alpha.webloc"])
    }

    func testDroppingIntoAFolderMovesWithoutRenumbering() throws {
        let folder = try model.createFolder(named: "Research", in: root)
        let entry = try makeEntry("Alpha.webloc")

        try model.drop(entry, .into, relativeTo: folder)

        XCTAssertEqual(try names(), ["Research"])
        XCTAssertEqual(try names(in: folder), ["Alpha.webloc"])
    }

    /// Reordering renumbers every sibling in the folder, subfolders included —
    /// the order is the filenames, so a partial renumbering would not hold.
    func testDroppingFromAnotherFolderMovesThenPlaces() throws {
        let folder = try model.createFolder(named: "Research", in: root)
        let incoming = try makeEntry("Zulu.webloc", in: folder)
        let anchor = try makeEntry("Alpha.webloc")

        let result = try model.drop(incoming, .before, relativeTo: anchor)

        XCTAssertEqual(
            try names(), ["010_Zulu.webloc", "020_Alpha.webloc", "030_Research"])
        XCTAssertEqual(result.lastPathComponent, "010_Zulu.webloc")
        XCTAssertEqual(try names(in: root.appendingPathComponent("030_Research")), [])
    }

    func testTheReturnedURLPointsAtTheDroppedItem() throws {
        let a = try makeEntry("Alpha.webloc")
        let b = try makeEntry("Beta.webloc")

        let result = try model.drop(b, .before, relativeTo: a)

        XCTAssertEqual(result.lastPathComponent, "010_Beta.webloc")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
}
