import XCTest
@testable import URLShelf

final class DropRouterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/shelf")

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: "/shelf/\(path)")
    }

    func testMovesAShelfFileIntoAnotherFolder() {
        XCTAssertEqual(
            DropRouter.action(for: file("Wiki.webloc"), into: file("research"), shelfRoot: root),
            .move(file("Wiki.webloc")))
    }

    func testMovesAFolderIntoAnotherFolder() {
        XCTAssertEqual(
            DropRouter.action(for: file("work"), into: file("research"), shelfRoot: root),
            .move(file("work")))
    }

    func testDroppingOnTheCurrentParentDoesNothing() {
        XCTAssertEqual(
            DropRouter.action(for: file("research/IANA.webloc"), into: file("research"), shelfRoot: root),
            .reject)
    }

    func testRefusesToDropAFolderOnItself() {
        XCTAssertEqual(
            DropRouter.action(for: file("work"), into: file("work"), shelfRoot: root),
            .reject)
    }

    /// Would detach the whole branch from the shelf.
    func testRefusesToDropAFolderIntoItsOwnSubtree() {
        XCTAssertEqual(
            DropRouter.action(for: file("work"), into: file("work/notes"), shelfRoot: root),
            .reject)
    }

    /// Dragging in a file from Documents must not relocate the user's file
    /// just because it landed on this tree.
    func testRefusesFilesFromOutsideTheShelf() {
        XCTAssertEqual(
            DropRouter.action(
                for: URL(fileURLWithPath: "/Users/someone/Documents/Notes.webloc"),
                into: file("research"),
                shelfRoot: root),
            .reject)
    }

    func testFilesAWebAddressDraggedFromABrowser() {
        let web = URL(string: "https://example.com")!
        XCTAssertEqual(
            DropRouter.action(for: web, into: file("research"), shelfRoot: root),
            .addEntry(web))
    }

    func testRefusesNonBrowsableSchemes() {
        XCTAssertEqual(
            DropRouter.action(
                for: URL(string: "mailto:someone@example.com")!,
                into: file("research"),
                shelfRoot: root),
            .reject)
    }
}
