import XCTest
@testable import URLShelf

final class WeblocFileTests: XCTestCase {
    private func xmlPlist(_ body: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \(body)
        </dict>
        </plist>
        """.utf8)
    }

    func testParsesPlainFinderWebloc() throws {
        let file = try WeblocFile.parse(xmlPlist("""
        <key>URL</key><string>https://example.com</string>
        """))
        XCTAssertEqual(file.url.absoluteString, "https://example.com")
        XCTAssertNil(file.openMode)
        XCTAssertNil(file.browserBundleID)
    }

    func testParsesCustomKeys() throws {
        let file = try WeblocFile.parse(xmlPlist("""
        <key>URL</key><string>https://example.com</string>
        <key>jp.ne.nlink.open</key><string>private</string>
        <key>jp.ne.nlink.browser</key><string>org.mozilla.firefox</string>
        """))
        XCTAssertEqual(file.openMode, .privateWindow)
        XCTAssertEqual(file.browserBundleID, "org.mozilla.firefox")
    }

    func testParsesBinaryPlist() throws {
        // Finder writes binary plists; hand-edited files are usually XML.
        let binary = try PropertyListSerialization.data(
            fromPropertyList: ["URL": "https://example.com"], format: .binary, options: 0)
        XCTAssertEqual(try WeblocFile.parse(binary).url.absoluteString, "https://example.com")
    }

    func testMissingURLIsRejected() {
        XCTAssertThrowsError(try WeblocFile.parse(xmlPlist("""
        <key>jp.ne.nlink.open</key><string>private</string>
        """))) { error in
            XCTAssertEqual(error as? WeblocError, .missingURL)
        }
    }

    func testWritesXMLNotBinary() throws {
        let data = try WeblocFile(url: URL(string: "https://example.com")!).serialized()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("<?xml"), "webloc files must stay greppable")
        XCTAssertTrue(text.contains("https://example.com"))
    }

    func testPreservesForeignKeys() throws {
        // url-shelf is one reader among many; another tool's keys must survive.
        let original = try WeblocFile.parse(xmlPlist("""
        <key>URL</key><string>https://example.com</string>
        <key>com.example.other</key><string>keep me</string>
        """))
        let reloaded = try WeblocFile.parse(original.serialized())
        XCTAssertEqual(reloaded.foreignKeys, ["com.example.other"])
    }

    func testClearingOpenModeRemovesTheKey() throws {
        var file = WeblocFile(url: URL(string: "https://example.com")!, openMode: .privateWindow)
        file.openMode = nil
        let reloaded = try WeblocFile.parse(file.serialized())
        XCTAssertNil(reloaded.openMode)
        XCTAssertEqual(reloaded.foreignKeys, [])
    }

    func testRoundTripThroughDisk() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("Entry.webloc")
        let original = WeblocFile(
            url: URL(string: "https://example.com/path?q=1")!,
            openMode: .privateWindow,
            browserBundleID: "com.google.Chrome")
        try original.write(to: fileURL)

        let reloaded = try WeblocFile.read(contentsOf: fileURL)
        XCTAssertEqual(reloaded.url, original.url)
        XCTAssertEqual(reloaded.openMode, .privateWindow)
        XCTAssertEqual(reloaded.browserBundleID, "com.google.Chrome")
    }
}
