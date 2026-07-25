import AppKit

/// What a menu item does when clicked.
private final class EntryTarget: NSObject {
    let fileURL: URL
    let folderURL: URL
    let useInverted: Bool

    init(fileURL: URL, folderURL: URL, useInverted: Bool) {
        self.fileURL = fileURL
        self.folderURL = folderURL
        self.useInverted = useInverted
    }
}

/// Owns the menu-bar item and its menu.
///
/// The shelf is re-read every time a menu opens (`menuNeedsUpdate`) rather than
/// watched with FSEvents: the menu is then always current and the app holds no
/// synchronization state that could drift from the filesystem. Submenus are
/// populated only when they open, so a deep tree costs nothing until visited.
@MainActor
final class StatusItemController: NSObject {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    /// Which folder each submenu shows. `NSMenu.delegate` is weak and menus are
    /// rebuilt constantly, so the mapping lives here rather than on the menus.
    private var folderForMenu: [ObjectIdentifier: URL] = [:]

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "books.vertical",
            accessibilityDescription: "URL Shelf")
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - Building

    private func populate(_ menu: NSMenu, from folder: URL) {
        do {
            let items = try model.shelf.children(of: folder)
            if items.isEmpty {
                menu.addItem(disabledItem("(empty)"))
            }
            for item in items {
                switch item {
                case .folder(let name, let url):
                    menu.addItem(folderItem(name: name, url: url))
                case .entry(let name, let fileURL):
                    addEntryItems(name: name, fileURL: fileURL, folder: folder, to: menu)
                }
            }
        } catch {
            menu.addItem(disabledItem("Cannot read this folder"))
        }
    }

    private func folderItem(name: String, url: URL) -> NSMenuItem {
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)

        let submenu = NSMenu(title: name)
        submenu.delegate = self
        folderForMenu[ObjectIdentifier(submenu)] = url
        item.submenu = submenu
        return item
    }

    /// Two items per entry: the resolved one, and an Option-key alternate that
    /// inverts normal ⇄ private. Either can be disabled on its own — an entry
    /// whose private mode is unavailable still opens normally, and vice versa.
    private func addEntryItems(name: String, fileURL: URL, folder: URL, to menu: NSMenu) {
        guard let plan = try? model.plan(forEntryAt: fileURL, in: folder) else {
            let broken = disabledItem(name)
            broken.toolTip = "This file is not a readable web location."
            menu.addItem(broken)
            return
        }

        let primary = entryItem(
            title: name,
            mode: plan.resolvedMode,
            outcome: plan.asResolved,
            target: EntryTarget(fileURL: fileURL, folderURL: folder, useInverted: false))
        menu.addItem(primary)

        let invertedMode = LaunchPlanner.inverted(plan.resolvedMode)
        let alternate = entryItem(
            title: "\(name) (\(label(for: invertedMode)))",
            mode: invertedMode,
            outcome: plan.inverted,
            target: EntryTarget(fileURL: fileURL, folderURL: folder, useInverted: true))
        alternate.keyEquivalentModifierMask = .option
        alternate.isAlternate = true
        menu.addItem(alternate)
    }

    private func entryItem(
        title: String,
        mode: OpenMode,
        outcome: Result<LaunchAction, LaunchBlocked>,
        target: EntryTarget
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(openEntry(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = target
        item.image = NSImage(
            systemSymbolName: mode == .privateWindow ? "eyeglasses" : "globe",
            accessibilityDescription: nil)

        if case .failure(let blocked) = outcome {
            // Disabled with a reason, never a silent downgrade to a normal open.
            item.action = nil
            item.isEnabled = false
            item.toolTip = AppModel.describe(blocked)
        }
        return item
    }

    private func label(for mode: OpenMode) -> String {
        mode == .privateWindow ? "Private Window" : "Normal Window"
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    // MARK: - Actions

    @objc private func openEntry(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? EntryTarget else { return }
        do {
            let plan = try model.plan(forEntryAt: target.fileURL, in: target.folderURL)
            switch target.useInverted ? plan.inverted : plan.asResolved {
            case .success(let action): model.run(action)
            case .failure(let blocked): model.present(blocked)
            }
        } catch {
            model.present(error)
        }
    }

    @objc private func chooseShelfFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your .webloc files."

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.setRoot(url)
        } catch {
            model.present(error)
        }
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let folder = folderForMenu[ObjectIdentifier(menu)] {
            populate(menu, from: folder)
            return
        }

        // Root menu: pick up config edits made since it was last opened.
        model.reloadConfig()
        folderForMenu.removeAll()

        if let root = model.rootURL {
            populate(menu, from: root)
        } else {
            menu.addItem(disabledItem("No shelf folder configured"))
        }

        menu.addItem(.separator())
        let choose = NSMenuItem(
            title: "Choose Shelf Folder…", action: #selector(chooseShelfFolder), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        if model.inventory.privateCapableBrowsers().isEmpty {
            let warning = disabledItem("No private-capable browser installed")
            warning.toolTip = "Safari cannot be opened in a private window from another app. "
                + "Install Firefox, Chrome, or Edge to use private entries."
            menu.addItem(warning)
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("URL Shelf \(AppInfo.version)"))
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
    }
}
