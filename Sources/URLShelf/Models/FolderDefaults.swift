import Foundation

/// Defaults declared by a folder for itself and everything below it, read from
/// `.url-shelf.toml`.
///
/// This is the one piece of metadata that is *not* stored in the `.webloc`
/// files: it belongs to the folder, so it cannot be broken by renaming or moving
/// an entry. Keys are top-level (no section header):
///
/// ```toml
/// open    = "private"
/// browser = "org.mozilla.firefox"
/// ```
struct FolderDefaults: Equatable {
    static let filename = ".url-shelf.toml"

    var openMode: OpenMode?
    var browserBundleID: String?

    static let empty = FolderDefaults(openMode: nil, browserBundleID: nil)

    var isEmpty: Bool { self == .empty }

    static func parse(_ text: String) -> FolderDefaults {
        let root = MiniTOML.parse(text)[""] ?? [:]
        return FolderDefaults(
            openMode: root["open"].flatMap(OpenMode.init(rawValue:)),
            browserBundleID: root["browser"].flatMap { $0.isEmpty ? nil : $0 })
    }

    func serialized() -> String {
        var lines = ["# url-shelf defaults for this folder and everything below it."]
        if let openMode {
            lines.append("open    = \(MiniTOML.quote(openMode.rawValue))")
        }
        if let browserBundleID {
            lines.append("browser = \(MiniTOML.quote(browserBundleID))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
