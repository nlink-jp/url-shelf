import Foundation

/// How an entry should be opened.
enum OpenMode: String, Equatable, CaseIterable {
    case normal
    case privateWindow = "private"
}

/// Which browser to use. `systemDefault` hands the URL to LaunchServices, so it
/// follows whatever the user sets as their default browser.
enum BrowserSelection: Equatable {
    case systemDefault
    case bundleID(String)

    /// Config files store `"default"` for the system default; anything else is a
    /// bundle ID. Bundle IDs are the canonical form everywhere — display names
    /// are presentation only, so they never round-trip through storage.
    init(configValue: String) {
        let trimmed = configValue.trimmingCharacters(in: .whitespaces)
        self = (trimmed.isEmpty || trimmed == "default") ? .systemDefault : .bundleID(trimmed)
    }

    var configValue: String {
        switch self {
        case .systemDefault: return "default"
        case .bundleID(let id): return id
        }
    }
}

/// Keys used inside a `.webloc` plist.
///
/// `URL` is the standard key every macOS tool reads — it must stay intact so
/// double-clicking in Finder keeps working. Everything url-shelf adds lives in a
/// reverse-DNS namespace that other readers ignore.
enum WeblocKey {
    static let url = "URL"
    static let open = "jp.ne.nlink.open"
    static let browser = "jp.ne.nlink.browser"
}
