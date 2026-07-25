import Foundation

enum WeblocError: Error, Equatable {
    case notADictionary
    case missingURL
    case malformedURL(String)
}

/// A `.webloc` file: a property list whose `URL` key holds the target.
///
/// The raw plist is kept so that keys written by other tools survive a
/// round-trip — url-shelf is one reader among many, not the owner of the file.
struct WeblocFile {
    private var plist: [String: Any]

    init(url: URL, openMode: OpenMode? = nil, browserBundleID: String? = nil) {
        plist = [WeblocKey.url: url.absoluteString]
        self.openMode = openMode
        self.browserBundleID = browserBundleID
    }

    private init(plist: [String: Any]) {
        self.plist = plist
    }

    var url: URL {
        get {
            // Validated on parse, and the setter only accepts a URL.
            URL(string: plist[WeblocKey.url] as? String ?? "") ?? URL(fileURLWithPath: "/")
        }
        set { plist[WeblocKey.url] = newValue.absoluteString }
    }

    var openMode: OpenMode? {
        get { (plist[WeblocKey.open] as? String).flatMap(OpenMode.init(rawValue:)) }
        set {
            if let newValue {
                plist[WeblocKey.open] = newValue.rawValue
            } else {
                plist.removeValue(forKey: WeblocKey.open)
            }
        }
    }

    var browserBundleID: String? {
        get { plist[WeblocKey.browser] as? String }
        set {
            if let newValue, !newValue.isEmpty {
                plist[WeblocKey.browser] = newValue
            } else {
                plist.removeValue(forKey: WeblocKey.browser)
            }
        }
    }

    /// Keys url-shelf does not own, preserved verbatim across a round-trip.
    var foreignKeys: [String] {
        plist.keys
            .filter { $0 != WeblocKey.url && $0 != WeblocKey.open && $0 != WeblocKey.browser }
            .sorted()
    }

    // MARK: - Serialization

    /// Accepts both binary and XML property lists — Finder writes binary, and
    /// hand-edited files are usually XML.
    static func parse(_ data: Data) throws -> WeblocFile {
        let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dict = raw as? [String: Any] else { throw WeblocError.notADictionary }
        guard let urlString = dict[WeblocKey.url] as? String else { throw WeblocError.missingURL }
        guard URL(string: urlString) != nil else { throw WeblocError.malformedURL(urlString) }
        return WeblocFile(plist: dict)
    }

    /// Always emits XML so the files stay greppable, diffable, and hand-editable.
    func serialized() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    static func read(contentsOf fileURL: URL) throws -> WeblocFile {
        try parse(Data(contentsOf: fileURL))
    }

    func write(to fileURL: URL) throws {
        try serialized().write(to: fileURL, options: .atomic)
    }
}
