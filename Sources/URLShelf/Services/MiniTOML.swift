import Foundation

/// The small TOML subset url-shelf's config files need.
///
/// Deliberately not a full TOML implementation: the config surface is a handful
/// of string values, and a dependency for that would cost more than it saves.
/// Supported: `[section]` headers, `key = "value"`, `#` comments, blank lines.
/// Values are always quoted strings. Anything else is ignored rather than
/// rejected, so a file a human extended by hand still loads.
enum MiniTOML {
    /// Section name → key → value. Keys before any header land in section `""`.
    static func parse(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var current = ""

        for rawLine in text.components(separatedBy: .newlines) {
            let line = stripComment(rawLine)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("["), line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast())
                    .trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            let rawValue = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let value = unquote(rawValue) else { continue }

            sections[current, default: [:]][key] = value
        }

        return sections
    }

    /// Quotes and escapes a value for writing.
    static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func stripComment(_ line: String) -> String {
        var inQuotes = false
        var escaped = false
        var out = ""

        for character in line {
            if escaped {
                out.append(character)
                escaped = false
                continue
            }
            switch character {
            case "\\" where inQuotes:
                out.append(character)
                escaped = true
            case "\"":
                inQuotes.toggle()
                out.append(character)
            case "#" where !inQuotes:
                return out.trimmingCharacters(in: .whitespaces)
            default:
                out.append(character)
            }
        }

        return out.trimmingCharacters(in: .whitespaces)
    }

    private static func unquote(_ value: String) -> String? {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return nil }
        let inner = value.dropFirst().dropLast()

        var out = ""
        var escaped = false
        for character in inner {
            if escaped {
                out.append(character == "n" ? "\n" : character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                out.append(character)
            }
        }
        return out
    }
}
