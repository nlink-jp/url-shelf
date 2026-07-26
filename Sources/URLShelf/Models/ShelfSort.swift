import Foundation

/// Whether folders and entries are grouped, or simply interleaved by name.
enum ShelfGrouping: String, CaseIterable, Equatable, Hashable {
    case foldersFirst = "folders-first"
    case entriesFirst = "entries-first"
    /// No grouping — folders and entries interleave by name, so a numbering
    /// scheme can order them against each other.
    case name

    var displayName: String {
        switch self {
        case .foldersFirst: return "Folders first"
        case .entriesFirst: return "Entries first"
        case .name: return "Name only"
        }
    }
}

/// How a folder's contents are ordered in the menu.
struct ShelfSort: Equatable, Hashable {
    var grouping: ShelfGrouping
    var descending: Bool

    static let `default` = ShelfSort(grouping: .foldersFirst, descending: false)

    /// Names compare naturally, so `2_` sorts before `10_` rather than after it:
    /// a number in a filename is read as a number.
    ///
    /// `descending` reverses the name order only; folders stay on the side the
    /// grouping puts them, because flipping that too would make one setting mean
    /// two things at once.
    func apply(to items: [ShelfItem]) -> [ShelfItem] {
        items.sorted { left, right in
            if grouping != .name, left.isFolder != right.isFolder {
                return grouping == .foldersFirst ? left.isFolder : right.isFolder
            }

            let comparison = left.url.lastPathComponent
                .localizedStandardCompare(right.url.lastPathComponent)
            return descending ? comparison == .orderedDescending : comparison == .orderedAscending
        }
    }
}
