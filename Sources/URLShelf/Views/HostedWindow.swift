import AppKit
import SwiftUI

/// Keeps the app regular for as long as any window is open.
///
/// An `.accessory` app cannot bring a window forward or give a text field a
/// caret, so it switches to `.regular` while showing one. Counted, because
/// closing one window must not demote the app while another is still open.
@MainActor
enum RegularActivation {
    private static var openWindows = 0

    static func begin() {
        openWindows += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func end() {
        openWindows = max(0, openWindows - 1)
        if openWindows == 0 {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// A plain `NSWindow` hosting a SwiftUI view.
///
/// Not a SwiftUI `Settings` scene: opening one imperatively depends on a private
/// AppKit selector that has not survived every macOS release. A window the app
/// owns behaves the same on every version.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    private let title: String
    private let size: NSSize
    private let content: () -> AnyView
    private var window: NSWindow?

    init<Content: View>(
        title: String,
        size: NSSize,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.size = size
        self.content = { AnyView(content()) }
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            window.title = title
            window.contentView = NSHostingView(rootView: content())
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            self.window = window
            RegularActivation.begin()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        RegularActivation.end()
    }
}
