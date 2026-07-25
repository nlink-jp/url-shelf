import Foundation

/// Global settings, stored at `~/.config/url-shelf/config.toml`.
///
/// A visible, greppable file rather than `UserDefaults`: the shelf itself is
/// plain files, and the settings that point at it should be inspectable the same
/// way.
struct AppConfig: Equatable {
    /// Absolute path to the shelf root. `nil` until the user picks one.
    var rootPath: String?
    /// Folder (relative to the root) that receives dropped URLs. Empty = the root.
    var inbox: String
    var normalBrowser: BrowserSelection
    /// Bundle ID of the browser used for private entries. `nil` when unset — in
    /// that state private entries are shown disabled rather than downgraded.
    var privateBrowser: String?

    static let `default` = AppConfig(
        rootPath: nil,
        inbox: "",
        normalBrowser: .systemDefault,
        privateBrowser: nil)

    var rootURL: URL? {
        rootPath.map { URL(fileURLWithPath: PathExpansion.expandingTilde($0)) }
    }

    static func defaultFileURL() -> URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/url-shelf/config.toml")
    }

    // MARK: - Serialization

    static func parse(_ text: String) -> AppConfig {
        let sections = MiniTOML.parse(text)
        let shelf = sections["shelf"] ?? [:]
        let browser = sections["browser"] ?? [:]

        return AppConfig(
            rootPath: shelf["root"].flatMap { $0.isEmpty ? nil : $0 },
            inbox: shelf["inbox"] ?? "",
            normalBrowser: BrowserSelection(configValue: browser["normal"] ?? "default"),
            privateBrowser: browser["private"].flatMap { $0.isEmpty ? nil : $0 })
    }

    func serialized() -> String {
        """
        [shelf]
        root    = \(MiniTOML.quote(rootPath ?? ""))
        inbox   = \(MiniTOML.quote(inbox))

        [browser]
        normal  = \(MiniTOML.quote(normalBrowser.configValue))
        private = \(MiniTOML.quote(privateBrowser ?? ""))

        """
    }

    static func read(contentsOf fileURL: URL) -> AppConfig {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return .default }
        return parse(text)
    }

    func write(to fileURL: URL) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try serialized().write(to: fileURL, atomically: true, encoding: .utf8)
    }
}

enum PathExpansion {
    /// `NSString.expandingTildeInPath` only expands a leading `~`, which is all
    /// the config needs — but it also rewrites paths that merely contain one.
    static func expandingTilde(_ path: String) -> String {
        path.hasPrefix("~") ? (path as NSString).expandingTildeInPath : path
    }
}
