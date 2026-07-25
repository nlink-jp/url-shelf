import AppKit

/// Owns the menu-bar item and its menu.
///
/// The shelf tree is rescanned every time the menu opens (`menuNeedsUpdate`)
/// rather than watched with FSEvents: the menu is then always current and the
/// app holds no synchronization state that could drift from the filesystem.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.image = NSImage(
            systemSymbolName: "books.vertical",
            accessibilityDescription: "URL Shelf")
        menu.delegate = self
        statusItem.menu = menu
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Phase 3: populate from the shelf tree — folders become submenus
        // (populated lazily when opened), .webloc files become items, each with
        // an Option-key alternate that inverts normal/private.
        menu.addItem(disabledItem("No shelf folder configured"))

        menu.addItem(.separator())
        menu.addItem(disabledItem("URL Shelf \(AppInfo.version)"))
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
