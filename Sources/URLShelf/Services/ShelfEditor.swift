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
