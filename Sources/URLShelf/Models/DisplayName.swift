import Foundation

/// Derives the label shown in the menu from a shelf filename.
///
/// Only the extension goes: the filename is the name, exactly as Finder shows
/// it. url-shelf once stripped a leading `01_` so that a numbering scheme could
/// order the menu invisibly, but ordering is a setting now, and a label that
/// silently differs from the filename is a small lie the app has no reason to
/// tell.
enum DisplayName {
    static func fromFilename(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }
}
