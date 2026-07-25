import Foundation

/// Derives the label shown in the menu from a shelf filename.
///
/// The filesystem is the canonical store, so menu ordering has to be expressed
/// in the filenames themselves (`01_Wiki.webloc`, `02 - Expenses.webloc`). The
/// prefix orders the entries but must not reach the menu.
enum DisplayName {
    /// Maximum digits treated as an ordering prefix. Kept short so that names
    /// legitimately starting with a year (`2026-07-26 notes.webloc`) survive
    /// intact — a 4-digit run is a date, not a sort key.
    private static let maxPrefixDigits = 3

    private static let separators: Set<Character> = [" ", "_", "-", "."]

    /// Strips the path extension and any ordering prefix.
    static func fromFilename(_ filename: String) -> String {
        strippingOrderPrefix((filename as NSString).deletingPathExtension)
    }

    /// Removes a leading `<digits><separator(s)>` run from an extension-less name.
    /// Returns the input unchanged when the result would be empty or when the
    /// digit run is too long to be a sort key.
    static func strippingOrderPrefix(_ stem: String) -> String {
        var rest = Substring(stem)

        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= maxPrefixDigits else { return stem }
        rest = rest.dropFirst(digits.count)

        var separatorCount = 0
        while let c = rest.first, separators.contains(c) {
            rest = rest.dropFirst()
            separatorCount += 1
        }

        guard separatorCount > 0, !rest.isEmpty else { return stem }
        return String(rest)
    }
}
