import AppKit
import SwiftUI

/// Hosts the SwiftUI settings view in a plain `NSWindow`.
///
/// Not a SwiftUI `Settings` scene: opening one imperatively depends on a private
/// AppKit selector that has not survived every macOS release. An `NSWindow` the
/// app owns behaves the same on every version.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            window.title = "URL Shelf Settings"
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
        }

        // An accessory app cannot bring a window forward or give it a caret, so
        // it becomes a regular app for as long as the window is open.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
