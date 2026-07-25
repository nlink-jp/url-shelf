import Foundation

enum ShelfEditError: Error, Equatable {
    case folderIntoItself
}

/// Mutating operations on the shelf. Behind a protocol so the rules — prefix
/// preservation, collision handling, trash-not-delete — are unit-testable
/// without touching a real Finder.
protocol ShelfEditing {
    @discardableResult
    func createFolder(named name: String, in parent: URL) throws -> URL
    @discardableResult
    func rename(_ url: URL, toDisplayName newName: String) throws -> URL
    @discardableResult
    func move(_ url: URL, to destination: URL) throws -> URL
    func trash(_ url: URL) throws
    /// Renumbers a folder's filename prefixes so its contents sort in the given
    /// order. Returns the new URL of each item, in order.
    @discardableResult
    func reorder(in folder: URL, to ordered: [URL]) throws -> [URL]
}

struct FileSystemShelfEditor: ShelfEditing {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    @discardableResult
    func createFolder(named name: String, in parent: URL) throws -> URL {
        let url = EntryNaming.uniqueURL(
            in: parent, base: EntryNaming.sanitize(name), extension: "", fileManager: fileManager)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @discardableResult
    func rename(_ url: URL, toDisplayName newName: String) throws -> URL {
        let filename = DisplayName.renamedFilename(url.lastPathComponent, to: newName)
        let destination = url.deletingLastPathComponent().appendingPathComponent(filename)
        guard destination.path != url.path else { return url }

        let unique = uniqueSibling(of: destination, avoiding: url)
        try fileManager.moveItem(at: url, to: unique)
        return unique
    }

    @discardableResult
    func move(_ url: URL, to destination: URL) throws -> URL {
        let source = url.standardizedFileURL
        let target = destination.standardizedFileURL

        // Already there: a no-op, not an error. The inspector re-selects the
        // current folder whenever it loads, and that must stay silent.
        guard source.deletingLastPathComponent().path != target.path else { return url }
        // Moving a folder inside itself would detach the subtree from the shelf.
        guard !target.path.hasPrefix(source.path + "/"), target.path != source.path else {
            throw ShelfEditError.folderIntoItself
        }

        let proposed = target.appendingPathComponent(url.lastPathComponent)
        let unique = uniqueSibling(of: proposed, avoiding: url)
        try fileManager.moveItem(at: url, to: unique)
        return unique
    }

    /// Trash, never unlink: a shelf entry is the user's data, and a mistake has
    /// to be recoverable the same way it would be in Finder.
    func trash(_ url: URL) throws {
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    /// Renaming in two phases, via hidden temporary names.
    ///
    /// A renumbering routinely swaps names between files (`010_A` ⇄ `020_B`), so
    /// renaming in place would collide with a name still held by another file.
    /// Everything moves to a temporary name first, then to its final one. If the
    /// second phase fails, the temporaries are put back.
    @discardableResult
    func reorder(in folder: URL, to ordered: [URL]) throws -> [URL] {
        let renames = try ShelfOrdering.renames(for: ordered.map(\.lastPathComponent))
        guard !renames.isEmpty else { return ordered }

        let planned = Dictionary(uniqueKeysWithValues: renames.map { ($0.from, $0.to) })
        var staged: [(temporary: URL, final: URL, original: URL)] = []

        for (index, rename) in renames.enumerated() {
            let original = folder.appendingPathComponent(rename.from)
            // Hidden, so a failure mid-flight leaves nothing visible in the menu.
            let temporary = folder.appendingPathComponent(".url-shelf-reorder-\(index)")
            try fileManager.moveItem(at: original, to: temporary)
            staged.append((temporary, folder.appendingPathComponent(rename.to), original))
        }

        for item in staged {
            do {
                try fileManager.moveItem(at: item.temporary, to: item.final)
            } catch {
                rollback(staged)
                throw error
            }
        }

        return ordered.map { url in
            planned[url.lastPathComponent]
                .map { folder.appendingPathComponent($0) } ?? url
        }
    }

    private func rollback(_ staged: [(temporary: URL, final: URL, original: URL)]) {
        for item in staged where fileManager.fileExists(atPath: item.temporary.path) {
            try? fileManager.moveItem(at: item.temporary, to: item.original)
        }
    }

    private func uniqueSibling(of proposed: URL, avoiding original: URL) -> URL {
        guard fileManager.fileExists(atPath: proposed.path),
              proposed.standardizedFileURL.path != original.standardizedFileURL.path
        else { return proposed }

        let stem = (proposed.lastPathComponent as NSString).deletingPathExtension
        return EntryNaming.uniqueURL(
            in: proposed.deletingLastPathComponent(),
            base: stem,
            extension: proposed.pathExtension,
            fileManager: fileManager)
    }
}
