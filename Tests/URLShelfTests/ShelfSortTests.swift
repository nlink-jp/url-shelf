import XCTest
@testable import URLShelf

final class ShelfSortTests: XCTestCase {
    private func items(_ names: [String]) -> [ShelfItem] {
        names.map { name in
            let url = URL(fileURLWithPath: "/shelf/\(name)")
            return name.hasSuffix(".webloc")
                ? .entry(name: DisplayName.fromFilename(name), fileURL: url)
                : .folder(name: DisplayName.fromFilename(name), url: url)
        }
    }

    private func names(_ sort: ShelfSort, _ input: [String]) -> [String] {
        sort.apply(to: items(input)).map(\.url.lastPathComponent)
    }

    private let mixed = ["Beta.webloc", "work", "Alpha.webloc", "research"]

    func testFoldersFirst() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .foldersFirst, descending: false), mixed),
            ["research", "work", "Alpha.webloc", "Beta.webloc"])
    }

    func testEntriesFirst() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .entriesFirst, descending: false), mixed),
            ["Alpha.webloc", "Beta.webloc", "research", "work"])
    }

    func testNameOnlyInterleaves() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .name, descending: false), mixed),
            ["Alpha.webloc", "Beta.webloc", "research", "work"])
    }

    /// Direction reverses names only. Flipping the grouping too would make one
    /// setting mean two things.
    func testDescendingKeepsFoldersOnTheirSide() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .foldersFirst, descending: true), mixed),
            ["work", "research", "Beta.webloc", "Alpha.webloc"])
    }

    /// Numeric prefixes are read as numbers, so 2 comes before 10.
    func testOrderingPrefixesCompareNaturally() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .name, descending: false),
                  ["10_Ten.webloc", "2_Two.webloc", "1_One.webloc"]),
            ["1_One.webloc", "2_Two.webloc", "10_Ten.webloc"])
    }

    /// The point of "Name only": a prefix can order a folder against an entry.
    func testNameOnlyLetsAPrefixOutrankAFolder() {
        XCTAssertEqual(
            names(ShelfSort(grouping: .name, descending: false),
                  ["02_work", "01_Wiki.webloc"]),
            ["01_Wiki.webloc", "02_work"])
    }

    func testDefaultIsFoldersFirstAscending() {
        XCTAssertEqual(ShelfSort.default, ShelfSort(grouping: .foldersFirst, descending: false))
    }
}
