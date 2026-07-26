import XCTest
@testable import URLShelf

final class DisplayNameTests: XCTestCase {
    func testDropsExtension() {
        XCTAssertEqual(DisplayName.fromFilename("経費.webloc"), "経費")
    }

    func testKeepsInternalDots() {
        XCTAssertEqual(DisplayName.fromFilename("example.com.webloc"), "example.com")
    }

    func testFoldersHaveNoExtensionToDrop() {
        XCTAssertEqual(DisplayName.fromFilename("研究"), "研究")
    }

    /// A number at the front is part of the name, not a hidden sort key.
    func testKeepsALeadingNumber() {
        XCTAssertEqual(DisplayName.fromFilename("01_社内Wiki.webloc"), "01_社内Wiki")
        XCTAssertEqual(DisplayName.fromFilename("2026-07-26 メモ.webloc"), "2026-07-26 メモ")
    }
}
