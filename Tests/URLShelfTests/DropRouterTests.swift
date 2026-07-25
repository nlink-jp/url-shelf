import XCTest
@testable import URLShelf

final class DropPositionTests: XCTestCase {
    func testFolderRowsHaveAnInsideBand() {
        XCTAssertEqual(DropPosition.from(relativeY: 0.1, isFolder: true), .before)
        XCTAssertEqual(DropPosition.from(relativeY: 0.5, isFolder: true), .into)
        XCTAssertEqual(DropPosition.from(relativeY: 0.9, isFolder: true), .after)
    }

    func testEntryRowsSplitInHalf() {
        XCTAssertEqual(DropPosition.from(relativeY: 0.4, isFolder: false), .before)
        XCTAssertEqual(DropPosition.from(relativeY: 0.6, isFolder: false), .after)
    }
}

final class DropRouterTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/shelf")

    private func file(_ path: String) -> URL {
        URL(fileURLWithPath: "/shelf/\(path)")
    }

    func testMovesAShelfFileIntoAFolder() {
        XCTAssertEqual(
            DropRouter.action(
                for: file("Wiki.webloc"), onto: file("research"),
                position: .into, shelfRoot: root),
            .move(file("Wiki.webloc")))
    }

    /// The distinction that makes reordering work: sitting in the folder already
    /// makes an "into" drop a no-op, but a "next to a sibling" drop meaningful.
    func testDroppingIntoTheCurrentFolderIsANoOpButNextToASiblingIsNot() {
        let entry = file("research/IANA.webloc")
        XCTAssertEqual(
            DropRouter.action(
                for: entry, onto: file("research"), position: .into, shelfRoot: root),
            .reject)
        XCTAssertEqual(
            DropRouter.action(
                for: entry, onto: file("research/Wiki.webloc"),
                position: .before, shelfRoot: root),
            .move(entry))
    }

    func testDroppingOnItselfIsRejected() {
        XCTAssertEqual(
            DropRouter.action(
                for: file("Wiki.webloc"), onto: file("Wiki.webloc"),
                position: .after, shelfRoot: root),
            .reject)
    }

    func testRefusesToDropAFolderIntoItsOwnSubtree() {
        XCTAssertEqual(
            DropRouter.action(
                for: file("work"), onto: file("work/notes"), position: .into, shelfRoot: root),
            .reject)
        XCTAssertEqual(
            DropRouter.action(
                for: file("work"), onto: file("work/notes/Deep.webloc"),
                position: .before, shelfRoot: root),
            .reject)
    }

    /// Dragging in a file from Documents must not relocate the user's file just
    /// because it landed on this tree.
    func testRefusesFilesFromOutsideTheShelf() {
        XCTAssertEqual(
            DropRouter.action(
                for: URL(fileURLWithPath: "/Users/someone/Documents/Notes.webloc"),
                onto: file("research"), position: .into, shelfRoot: root),
            .reject)
    }

    func testFilesAWebAddressDraggedFromABrowser() {
        let web = URL(string: "https://example.com")!
        XCTAssertEqual(
            DropRouter.action(for: web, onto: file("research"), position: .into, shelfRoot: root),
            .addEntry(web))
    }

    func testRefusesNonBrowsableSchemes() {
        XCTAssertEqual(
            DropRouter.action(
                for: URL(string: "mailto:someone@example.com")!,
                onto: file("research"), position: .into, shelfRoot: root),
            .reject)
    }
}
