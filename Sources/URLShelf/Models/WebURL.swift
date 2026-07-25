import Foundation

/// Parsing a dropped or pasted string into something worth handing to a browser.
///
/// Not on the drop view: the same rule applies to the clipboard prefill and to
/// tree drops, and it is pure parsing rather than view logic.
enum WebURL {
    /// Schemes the app would ever ask a browser to open.
    private static let allowedSchemes: Set<String> = ["http", "https", "file", "ftp"]

    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        // A bare "example.com" is rejected: guessing a scheme for a dropped
        // fragment would open something the user did not point at.
        return allowedSchemes.contains(scheme) ? url : nil
    }
}
