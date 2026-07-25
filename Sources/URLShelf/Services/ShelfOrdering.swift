import Foundation

enum ShelfOrderingError: Error, Equatable {
    /// More items than a three-digit prefix can number.
    case folderTooLarge(count: Int)
}

/// Turns a desired order into filename renames.
///
/// Order lives in the filenames themselves, because the filesystem is the only
/// source of truth — there is no sidecar recording positions that Finder could
/// contradict. Reordering therefore *is* renaming, and the whole folder is
/// renumbered so the resulting order is exact rather than dependent on whatever
/// prefixes happened to be there before.
enum ShelfOrdering {
    /// Prefixes stay within three digits: a four-digit run reads as a year, and
    /// `DisplayName` deliberately refuses to treat those as ordering.
    static let maxItems = 999
    /// Step 10 leaves room to hand-insert between two entries in Finder.
    private static let preferredStep = 10

    static func step(forCount count: Int) -> Int {
        count * preferredStep <= maxItems ? preferredStep : 1
    }

    static func prefix(forPosition position: Int, step: Int) -> String {
        String(format: "%03d_", (position + 1) * step)
    }

    /// The renames that put `orderedFilenames` in exactly that order.
    /// Files already correctly named are left alone.
    static func renames(for orderedFilenames: [String]) throws -> [(from: String, to: String)] {
        guard orderedFilenames.count <= maxItems else {
            throw ShelfOrderingError.folderTooLarge(count: orderedFilenames.count)
        }
        let step = step(forCount: orderedFilenames.count)

        return orderedFilenames.enumerated().compactMap { position, filename in
            let renamed = renumbered(filename, position: position, step: step)
            return renamed == filename ? nil : (from: filename, to: renamed)
        }
    }

    static func renumbered(_ filename: String, position: Int, step: Int) -> String {
        let stem = (filename as NSString).deletingPathExtension
        let pathExtension = (filename as NSString).pathExtension
        let name = prefix(forPosition: position, step: step)
            + DisplayName.strippingOrderPrefix(stem)
        return pathExtension.isEmpty ? name : "\(name).\(pathExtension)"
    }

    /// The order that results from taking `moved` out of `current` and putting it
    /// back next to `target`.
    static func reordered(
        _ current: [URL],
        moving moved: URL,
        to position: DropPosition,
        relativeTo target: URL
    ) -> [URL] {
        var result = current.filter { $0.standardizedFileURL != moved.standardizedFileURL }
        guard let index = result.firstIndex(where: {
            $0.standardizedFileURL == target.standardizedFileURL
        }) else {
            return current
        }

        result.insert(moved, at: position == .before ? index : index + 1)
        return result
    }
}

/// Where a drop lands relative to the row under the pointer.
enum DropPosition: Equatable {
    case before
    case after
    /// Inside the row's folder.
    case into

    /// Folders take the middle of the row as "inside"; an entry has no inside,
    /// so its midpoint simply splits before from after.
    static func from(relativeY: Double, isFolder: Bool) -> DropPosition {
        if isFolder {
            if relativeY < 0.25 { return .before }
            if relativeY > 0.75 { return .after }
            return .into
        }
        return relativeY < 0.5 ? .before : .after
    }
}
