import Foundation

/// What a URL dropped on a row in the tree should do.
enum DropAction: Equatable {
    /// A shelf file dragged somewhere else — into a folder, or next to a row.
    case move(URL)
    /// A web address dragged in from a browser.
    case addEntry(URL)
    case reject
}

/// Decides what a drop means, separately from the view, so the rules are
/// testable without a drag.
enum DropRouter {
    static func action(
        for dropped: URL,
        onto target: URL,
        position: DropPosition,
        shelfRoot: URL
    ) -> DropAction {
        guard dropped.isFileURL else {
            return WebURL.parse(dropped.absoluteString).map(DropAction.addEntry) ?? .reject
        }

        let source = dropped.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        let root = shelfRoot.standardizedFileURL.path

        // Files from outside the shelf are not adopted: moving something out of
        // the user's Documents because it landed on a menu tree is a surprise.
        guard source.hasPrefix(root + "/") else { return .reject }

        // Dropping something on itself.
        guard source != targetPath else { return .reject }

        let destination = position == .into ? targetPath : parentPath(of: targetPath)

        // Into itself or its own subtree would detach the branch from the shelf.
        guard destination != source, !destination.hasPrefix(source + "/") else { return .reject }

        // Landing inside the folder it already sits in changes nothing — but
        // dropping *next to* a sibling is a reorder, which very much does.
        if position == .into, parentPath(of: source) == destination { return .reject }

        return .move(dropped)
    }

    private static func parentPath(of path: String) -> String {
        (path as NSString).deletingLastPathComponent
    }
}
