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
    private let settings: SettingsWindowController

    /// Which folder each submenu shows. `NSMenu.delegate` is weak and menus are
    /// rebuilt constantly, so the mapping lives here rather than on the menus.
    private var folderForMenu: [ObjectIdentifier: URL] = [:]

    init(model: AppModel) {
        self.model = model
        settings = SettingsWindowController(model: model)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = Self.defaultImage
        menu.delegate = self
        statusItem.menu = menu
        installDropTarget()
    }

    private static let defaultImage = NSImage(
        systemSymbolName: "books.vertical", accessibilityDescription: "URL Shelf")

    private func installDropTarget() {
        guard let button = statusItem.button else { return }
        let drop = URLDropView(frame: button.bounds)
        drop.autoresizingMask = [.width, .height]
        drop.button = button
        drop.onDrop = { [weak self] url in self?.acceptDroppedURL(url) ?? false }
        button.addSubview(drop)
    }

    private func acceptDroppedURL(_ url: URL) -> Bool {
        do {
            try model.addEntry(url: url, in: model.inboxURL())
            confirmDrop()
            return true
        } catch {
            model.present(error)
            return false
        }
    }

    /// A dropped URL vanishes into a folder the user cannot see from here, so
    /// the icon acknowledges it briefly — quieter than an alert, and enough to
    /// tell "saved" from "nothing happened".
    private func confirmDrop() {
        statusItem.button?.image = NSImage(
            systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Saved")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.statusItem.button?.image = Self.defaultImage
        }
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

        // A second alternate on Command: the file behind an entry has to be
        // reachable, since the filesystem is where the shelf is actually edited.
        let reveal = NSMenuItem(
            title: "\(name) (Reveal in Finder)",
            action: #selector(revealInFinder(_:)),
            keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = EntryTarget(
            fileURL: fileURL, folderURL: folder, useInverted: false)
        reveal.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        reveal.keyEquivalentModifierMask = .command
        reveal.isAlternate = true
        menu.addItem(reveal)
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

    /// The private browser is the one setting worth switching from the menu:
    /// which browser an investigation should be isolated in changes with the
    /// task, while the root and the normal browser are set once (in Settings).
    private func privateBrowserMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Private Browser", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: item.title)

        let candidates = model.inventory.privateCapableBrowsers()
        if candidates.isEmpty {
            submenu.addItem(disabledItem("No capable browser installed"))
        }
        for capability in candidates {
            let entry = NSMenuItem(
                title: capability.displayName,
                action: #selector(selectPrivateBrowser(_:)),
                keyEquivalent: "")
            entry.target = self
            entry.representedObject = capability.bundleID
            entry.state = model.config.privateBrowser == capability.bundleID ? .on : .off
            submenu.addItem(entry)
        }

        item.submenu = submenu
        return item
    }

    @objc private func selectPrivateBrowser(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        do {
            try model.setPrivateBrowser(bundleID)
        } catch {
            model.present(error)
        }
    }

    @objc private func openSettings() {
        settings.show()
    }

    @objc private func openAbout() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func openShelfFolder(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func revealInFinder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? EntryTarget else { return }
        NSWorkspace.shared.activateFileViewerSelecting([target.fileURL])
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

        // Stated inline, not just as a tooltip: a disabled entry with no visible
        // explanation reads as a broken app rather than as a setting to make.
        if model.rootURL == nil {
            menu.addItem(disabledItem("Choose a shelf folder in Settings to begin"))
        } else if model.needsPrivateBrowserChoice {
            menu.addItem(disabledItem("Private entries need a browser — choose one below"))
        } else if model.inventory.privateCapableBrowsers().isEmpty {
            let warning = disabledItem("No private-capable browser installed")
            warning.toolTip = "Safari cannot be opened in a private window from another app. "
                + "Install Firefox, Chrome, or Edge to use private entries."
            menu.addItem(warning)
        }

        menu.addItem(privateBrowserMenuItem())

        if let root = model.rootURL {
            let reveal = NSMenuItem(
                title: "Open Shelf Folder in Finder",
                action: #selector(openShelfFolder),
                keyEquivalent: "")
            reveal.target = self
            reveal.representedObject = root
            menu.addItem(reveal)
        }

        let settingsItem = NSMenuItem(
            title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let about = NSMenuItem(
            title: "About URL Shelf \(AppInfo.version)",
            action: #selector(openAbout),
            keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"))
    }
}
