import Foundation

/// What a URL dropped onto a folder in the tree should do.
enum DropAction: Equatable {
    /// A shelf file dragged to another folder.
    case move(URL)
    /// A web address dragged in from a browser.
    case addEntry(URL)
    case reject
}

/// Decides what a drop means, separately from the view, so the rules are
/// testable without a drag.
enum DropRouter {
    static func action(for dropped: URL, into folder: URL, shelfRoot: URL) -> DropAction {
        guard dropped.isFileURL else {
            return WebURL.parse(dropped.absoluteString).map(DropAction.addEntry) ?? .reject
        }

        let source = dropped.standardizedFileURL.path
        let destination = folder.standardizedFileURL.path
        let root = shelfRoot.standardizedFileURL.path

        // Files from outside the shelf are not adopted: moving something out of
        // the user's Documents because it landed on a menu tree is a surprise.
        guard source.hasPrefix(root + "/") else { return .reject }

        // Into itself or its own subtree would detach the branch from the shelf.
        guard destination != source, !destination.hasPrefix(source + "/") else { return .reject }

        // Already there — nothing to do, and no error worth showing.
        guard (dropped.deletingLastPathComponent().standardizedFileURL.path) != destination else {
            return .reject
        }

        return .move(dropped)
    }
}
