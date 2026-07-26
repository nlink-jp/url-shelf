import XCTest
@testable import URLShelf

final class MiniTOMLTests: XCTestCase {
    func testParsesSectionsAndKeys() {
        let toml = """
        [shelf]
        root  = "~/Documents/URL Shelf"
        inbox = ""

        [browser]
        normal = "default"
        """
        let parsed = MiniTOML.parse(toml)
        XCTAssertEqual(parsed["shelf"]?["root"], "~/Documents/URL Shelf")
        XCTAssertEqual(parsed["shelf"]?["inbox"], "")
        XCTAssertEqual(parsed["browser"]?["normal"], "default")
    }

    func testKeysBeforeAnyHeaderLandInRootSection() {
        XCTAssertEqual(MiniTOML.parse(#"open = "private""#)[""]?["open"], "private")
    }

    func testStripsComments() {
        let parsed = MiniTOML.parse("""
        # leading comment
        open = "private"   # trailing comment
        """)
        XCTAssertEqual(parsed[""]?["open"], "private")
    }

    func testKeepsHashInsideQuotes() {
        XCTAssertEqual(MiniTOML.parse(#"root = "~/a#b""#)[""]?["root"], "~/a#b")
    }

    func testUnescapesQuotesAndBackslashes() {
        XCTAssertEqual(MiniTOML.parse(#"root = "a\"b\\c""#)[""]?["root"], #"a"b\c"#)
    }

    func testIgnoresUnquotedAndMalformedValues() {
        let parsed = MiniTOML.parse("""
        bare = 42
        novalue
        ok = "yes"
        """)
        XCTAssertNil(parsed[""]?["bare"])
        XCTAssertNil(parsed[""]?["novalue"])
        XCTAssertEqual(parsed[""]?["ok"], "yes")
    }

    func testQuoteRoundTrip() {
        let value = #"a"b\c"#
        let parsed = MiniTOML.parse("k = \(MiniTOML.quote(value))")
        XCTAssertEqual(parsed[""]?["k"], value)
    }
}

final class FolderDefaultsTests: XCTestCase {
    func testParsesBothKeys() {
        let defaults = FolderDefaults.parse("""
        open    = "private"
        browser = "org.mozilla.firefox"
        """)
        XCTAssertEqual(defaults.openMode, .privateWindow)
        XCTAssertEqual(defaults.browserBundleID, "org.mozilla.firefox")
    }

    func testEmptyFileIsEmptyDefaults() {
        XCTAssertTrue(FolderDefaults.parse("").isEmpty)
    }

    func testUnknownOpenValueIsIgnored() {
        XCTAssertNil(FolderDefaults.parse(#"open = "incognito""#).openMode)
    }

    func testRoundTrip() {
        let original = FolderDefaults(openMode: .privateWindow, browserBundleID: "com.google.Chrome")
        XCTAssertEqual(FolderDefaults.parse(original.serialized()), original)
    }
}

final class AppConfigTests: XCTestCase {
    func testDefaultsWhenFileIsEmpty() {
        XCTAssertEqual(AppConfig.parse(""), .default)
    }

    func testParsesFullConfig() {
        let config = AppConfig.parse("""
        [shelf]
        root    = "~/Documents/URL Shelf"
        inbox   = "inbox"

        [browser]
        normal  = "com.apple.Safari"
        private = "org.mozilla.firefox"
        """)
        XCTAssertEqual(config.rootPath, "~/Documents/URL Shelf")
        XCTAssertEqual(config.inbox, "inbox")
        XCTAssertEqual(config.normalBrowser, .bundleID("com.apple.Safari"))
        XCTAssertEqual(config.privateBrowser, "org.mozilla.firefox")
    }

    func testEmptyPrivateBrowserStaysUnset() {
        // Unset must not become a browser choice — it is what makes private
        // entries show as disabled instead of opening normally.
        let config = AppConfig.parse("""
        [browser]
        private = ""
        """)
        XCTAssertNil(config.privateBrowser)
    }

    func testDefaultKeywordMapsToSystemDefault() {
        let config = AppConfig.parse("""
        [browser]
        normal = "default"
        """)
        XCTAssertEqual(config.normalBrowser, .systemDefault)
    }

    func testRoundTrip() {
        let original = AppConfig(
            rootPath: "~/Documents/URL Shelf",
            inbox: "inbox",
            sort: ShelfSort(grouping: .entriesFirst, descending: true),
            normalBrowser: .bundleID("com.google.Chrome"),
            privateBrowser: "org.mozilla.firefox")
        XCTAssertEqual(AppConfig.parse(original.serialized()), original)
    }

    func testSortDefaultsWhenAbsentOrUnknown() {
        XCTAssertEqual(AppConfig.parse("").sort, .default)
        XCTAssertEqual(AppConfig.parse("""
        [shelf]
        sort = "sideways"
        """).sort, .default)
    }

    func testParsesSortSettings() {
        let config = AppConfig.parse("""
        [shelf]
        sort  = "entries-first"
        order = "descending"
        """)
        XCTAssertEqual(config.sort, ShelfSort(grouping: .entriesFirst, descending: true))
    }

    func testRootURLExpandsTilde() {
        let config = AppConfig.parse(#"""
        [shelf]
        root = "~/Shelf"
        """#)
        XCTAssertEqual(config.rootURL?.path, NSHomeDirectory() + "/Shelf")
    }
}
