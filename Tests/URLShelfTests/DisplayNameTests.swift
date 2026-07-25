import XCTest
@testable import URLShelf

final class DisplayNameTests: XCTestCase {
    func testDropsExtension() {
        XCTAssertEqual(DisplayName.fromFilename("経費.webloc"), "経費")
    }

    func testStripsUnderscoreOrderPrefix() {
        XCTAssertEqual(DisplayName.fromFilename("01_社内Wiki.webloc"), "社内Wiki")
    }

    func testStripsSpacedHyphenOrderPrefix() {
        XCTAssertEqual(DisplayName.fromFilename("10 - Docs.webloc"), "Docs")
    }

    func testKeepsYearPrefixIntact() {
        // 4 digits is a date, not a sort key.
        XCTAssertEqual(DisplayName.fromFilename("2026-07-26 メモ.webloc"), "2026-07-26 メモ")
    }

    func testKeepsPurelyNumericName() {
        XCTAssertEqual(DisplayName.fromFilename("007.webloc"), "007")
    }

    func testKeepsDigitsWithoutSeparator() {
        XCTAssertEqual(DisplayName.fromFilename("3Dプリンタ.webloc"), "3Dプリンタ")
    }

    func testKeepsInternalDots() {
        XCTAssertEqual(DisplayName.fromFilename("example.com.webloc"), "example.com")
    }
}
