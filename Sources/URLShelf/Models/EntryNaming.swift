import Foundation

enum ShelfError: Error, Equatable {
    case noRootConfigured
}

/// Chooses the filename for a new entry.
///
/// The filename is the entry's identity — it is what the menu shows and what the
/// user sorts with — so it has to be readable in Finder and safe on disk.
enum EntryNaming {
    /// `/` is the path separator and `:` is its legacy Finder counterpart; both
    /// are silently transformed by the filesystem, so neither may reach a name.
    private static let forbidden = CharacterSet(charactersIn: "/:")

    static func sanitize(_ name: String) -> String {
        // Trailing separators are trimmed too: a name of only forbidden
        // characters would otherwise become a filename of bare dashes.
        var trimmable = CharacterSet.whitespacesAndNewlines
        trimmable.insert(charactersIn: "-")

        let cleaned = name
            .components(separatedBy: forbidden)
            .joined(separator: "-")
            .trimmingCharacters(in: trimmable)

        // A leading dot would hide the entry from the menu, which skips dotfiles.
        let unhidden = cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
        return unhidden.isEmpty ? "Untitled" : String(unhidden.prefix(200))
    }

    /// Falls back to the host, then the whole URL — no network lookup is made to
    /// find a page title, since the app never talks to the network.
    static func filename(for url: URL, preferred: String?) -> String {
        if let preferred, !preferred.trimmingCharacters(in: .whitespaces).isEmpty {
            return sanitize(preferred)
        }
        if let host = url.host {
            let stripped = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            return sanitize(stripped)
        }
        return sanitize(url.absoluteString)
    }

    /// Appends " 2", " 3", … rather than overwriting: an existing entry is the
    /// user's data, not a cache.
    static func uniqueURL(
        in folder: URL,
        base: String,
        extension pathExtension: String,
        fileManager: FileManager = .default
    ) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(pathExtension)
        var counter = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder
                .appendingPathComponent("\(base) \(counter)")
                .appendingPathExtension(pathExtension)
            counter += 1
        }
        return candidate
    }
}
