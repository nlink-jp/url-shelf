import Foundation

/// One row of the shelf, as it will appear in the menu.
enum ShelfItem: Equatable {
    case folder(name: String, url: URL)
    case entry(name: String, fileURL: URL)

    var name: String {
        switch self {
        case .folder(let name, _), .entry(let name, _): return name
        }
    }

    var url: URL {
        switch self {
        case .folder(_, let url), .entry(_, let url): return url
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

protocol ShelfReading {
    /// One level only — submenus are populated when they open, not up front.
    func children(of folder: URL) throws -> [ShelfItem]
    func defaults(at folder: URL) -> FolderDefaults
}

/// Reads the shelf straight from the filesystem.
///
/// There is no index and no cache: the tree is re-read whenever the menu opens,
/// so rearranging folders in Finder while the app runs cannot desynchronize
/// anything. The filesystem is the only source of truth.
struct FileSystemShelf: ShelfReading {
    static let entryExtension = "webloc"

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func children(of folder: URL) throws -> [ShelfItem] {
        let urls = try fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles])

        let items: [ShelfItem] = urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])

            // A bundle (.app, .rtfd) is a directory but not a shelf folder.
            if values?.isDirectory == true, values?.isPackage != true {
                return .folder(name: DisplayName.fromFilename(url.lastPathComponent), url: url)
            }
            guard url.pathExtension.lowercased() == Self.entryExtension else { return nil }
            return .entry(name: DisplayName.fromFilename(url.lastPathComponent), fileURL: url)
        }

        // Sorted by filename, not display name, so an ordering prefix does its
        // job. This is a stable base order; how it is presented is ShelfSort's.
        return ShelfSort(grouping: .name, descending: false).apply(to: items)
    }

    func defaults(at folder: URL) -> FolderDefaults {
        let url = folder.appendingPathComponent(FolderDefaults.filename)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .empty }
        return FolderDefaults.parse(text)
    }
}

extension ShelfReading {
    /// Folder defaults from `root` down to `folder`, root first, so that the
    /// nearest ancestor is last and therefore wins.
    ///
    /// Returns just the root's defaults if `folder` is not inside `root`.
    func defaultsChain(from root: URL, to folder: URL) -> [FolderDefaults] {
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let leafPath = folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents

        guard leafPath.count >= rootPath.count, Array(leafPath.prefix(rootPath.count)) == rootPath
        else {
            return [defaults(at: root)]
        }

        var current = root.standardizedFileURL.resolvingSymlinksInPath()
        var chain = [defaults(at: current)]
        for component in leafPath.dropFirst(rootPath.count) {
            current.appendPathComponent(component)
            chain.append(defaults(at: current))
        }
        return chain
    }
}
