import AppKit
import SwiftUI

/// Tree on the left, inspector on the right.
///
/// Exists for the one thing Finder cannot do — editing the metadata inside a
/// `.webloc` — with the file operations that naturally belong beside it. The
/// filesystem stays authoritative: the tree is re-read after every change, and
/// rearranging the folder in Finder while this window is open is fine.
struct ShelfView: View {
    @ObservedObject var model: AppModel

    @State private var selection: String?
    @State private var errorMessage: String?
    @State private var pendingDeletion: ShelfNode?
    @State private var dropTarget: String?

    var body: some View {
        HSplitView {
            treePane
                .frame(minWidth: 220, idealWidth: 280)
            inspectorPane
                .frame(minWidth: 300)
        }
        .frame(minWidth: 620, minHeight: 420)
        .alert(item: $pendingDeletion) { node in
            Alert(
                title: Text("Move “\(node.name)” to the Trash?"),
                message: Text(node.isFolder
                    ? "Everything inside it goes to the Trash too. You can put it back from Finder."
                    : "You can put it back from Finder."),
                primaryButton: .destructive(Text("Move to Trash")) { trash(node) },
                secondaryButton: .cancel())
        }
    }

    // MARK: - Tree

    private var treePane: some View {
        VStack(spacing: 0) {
            if let tree = model.tree() {
                List(selection: $selection) {
                    OutlineGroup([tree], children: \.children) { node in
                        row(for: node)
                    }
                }
                .listStyle(.sidebar)
            } else {
                Spacer()
                Text("Choose a shelf folder in Settings.")
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()
            HStack(spacing: 12) {
                Button(action: newFolder) {
                    Image(systemName: "folder.badge.plus")
                }
                .help("New folder inside the selection")
                .disabled(model.rootURL == nil)

                Button(action: { pendingDeletion = selectedNode }) {
                    Image(systemName: "trash")
                }
                .help("Move to Trash")
                .disabled(selectedNode == nil || selectedNode?.url == model.rootURL)

                Spacer()

                Button(action: revealSelection) {
                    Image(systemName: "arrow.up.forward.app")
                }
                .help("Reveal in Finder")
                .disabled(selectedNode == nil)
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    /// Rows are draggable, folders are drop targets. Dropping is only a *move*
    /// between folders — reordering within one would mean renumbering filename
    /// prefixes, which ADR-0001 deliberately left out.
    @ViewBuilder
    private func row(for node: ShelfNode) -> some View {
        let label = Label(node.name, systemImage: node.isFolder ? "folder" : "globe")
            .tag(node.id)
            .draggable(node.url)

        if node.isFolder {
            label
                .background(dropTarget == node.id ? Color.accentColor.opacity(0.25) : .clear)
                .dropDestination(for: URL.self) { urls, _ in
                    accept(urls, into: node)
                } isTargeted: { targeted in
                    dropTarget = targeted ? node.id : nil
                }
        } else {
            label
        }
    }

    private func accept(_ urls: [URL], into folder: ShelfNode) -> Bool {
        guard let root = model.rootURL else { return false }
        var handled = false

        for url in urls {
            switch DropRouter.action(for: url, into: folder.url, shelfRoot: root) {
            case .move(let source):
                do {
                    let moved = try model.move(source, to: folder.url)
                    selection = moved.path
                    errorMessage = nil
                    handled = true
                } catch {
                    errorMessage = AppModel.describe(error)
                }
            case .addEntry(let webURL):
                do {
                    let added = try model.addEntry(url: webURL, in: folder.url)
                    selection = added.path
                    errorMessage = nil
                    handled = true
                } catch {
                    errorMessage = AppModel.describe(error)
                }
            case .reject:
                continue
            }
        }
        return handled
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorPane: some View {
        if let node = selectedNode, node.url != model.rootURL {
            if node.isFolder {
                FolderInspector(
                    model: model, node: node,
                    onError: { errorMessage = $0 },
                    onRelocated: { selection = $0.path })
                    .id(node.id)
            } else {
                EntryInspector(
                    model: model, node: node,
                    onError: { errorMessage = $0 },
                    onRelocated: { selection = $0.path })
                    .id(node.id)
            }
        } else {
            VStack {
                Spacer()
                Text("Select an entry or folder.").foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(.red).padding()
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Actions

    private var selectedNode: ShelfNode? {
        guard let selection, let tree = model.tree() else { return nil }
        return Self.find(selection, in: tree)
    }

    static func find(_ id: String, in node: ShelfNode) -> ShelfNode? {
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = find(id, in: child) { return found }
        }
        return nil
    }

    private func newFolder() {
        // A folder lands inside the selected folder, or beside a selected entry.
        let parent: URL? = {
            guard let node = selectedNode else { return model.rootURL }
            return node.isFolder ? node.url : node.url.deletingLastPathComponent()
        }()
        guard let parent else { return }

        do {
            let url = try model.createFolder(named: "New Folder", in: parent)
            selection = url.path
            errorMessage = nil
        } catch {
            errorMessage = AppModel.describe(error)
        }
    }

    private func trash(_ node: ShelfNode) {
        do {
            try model.trash(node.url)
            selection = nil
            errorMessage = nil
        } catch {
            errorMessage = AppModel.describe(error)
        }
    }

    private func revealSelection() {
        guard let node = selectedNode else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }
}

// MARK: - Entry inspector

private struct EntryInspector: View {
    @ObservedObject var model: AppModel
    let node: ShelfNode
    var onError: (String?) -> Void
    var onRelocated: (URL) -> Void

    @State private var name = ""
    @State private var urlText = ""
    @State private var openMode: OpenMode?
    @State private var browser: String?
    @State private var folder = ""

    var body: some View {
        Form {
            Section("Entry") {
                TextField("Name", text: $name)
                    .onSubmit(commitName)
                TextField("URL", text: $urlText)
                    .onSubmit(commitURL)
            }

            Section("Opening") {
                Picker("Open", selection: $openMode) {
                    Text("Inherit").tag(OpenMode?.none)
                    Text("Normal window").tag(OpenMode?.some(.normal))
                    Text("Private window").tag(OpenMode?.some(.privateWindow))
                }
                .onChange(of: openMode) { newValue in
                    apply { try model.updateEntry(at: node.url, openMode: .some(newValue)) }
                }

                Picker("Browser", selection: $browser) {
                    Text("Inherit").tag(String?.none)
                    ForEach(model.inventory.installedBrowsers(), id: \.bundleID) { candidate in
                        Text(candidate.displayName).tag(String?.some(candidate.bundleID))
                    }
                }
                .onChange(of: browser) { newValue in
                    apply { try model.updateEntry(at: node.url, browserBundleID: .some(newValue)) }
                }
            }

            Section("Location") {
                FolderPicker(model: model, selection: $folder, current: node.url) { destination in
                    relocate { try model.move(node.url, to: destination) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        name = node.name
        folder = currentFolderPath
        guard let entry = try? model.entry(at: node.url) else {
            onError("This file is not a readable web location.")
            return
        }
        urlText = entry.url.absoluteString
        openMode = entry.openMode
        browser = entry.browserBundleID
    }

    private var currentFolderPath: String {
        guard let root = model.rootURL else { return "" }
        let parent = node.url.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        guard parent.hasPrefix(rootPath) else { return "" }
        return String(parent.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func commitName() {
        relocate { try model.rename(node.url, toDisplayName: name) }
    }

    private func commitURL() {
        guard let url = URL(string: urlText.trimmingCharacters(in: .whitespaces)),
              url.scheme != nil else {
            onError("That is not a URL. Include the scheme, e.g. https://example.com")
            return
        }
        apply { try model.updateEntry(at: node.url, url: url) }
    }

    private func apply(_ work: () throws -> Void) {
        do {
            try work()
            onError(nil)
        } catch {
            onError(AppModel.describe(error))
        }
    }

    /// Renaming and moving change the file's URL, which is the selection's
    /// identity — without this the inspector would empty itself after an edit.
    private func relocate(_ work: () throws -> URL) {
        do {
            onRelocated(try work())
            onError(nil)
        } catch {
            onError(AppModel.describe(error))
        }
    }
}

// MARK: - Folder inspector

private struct FolderInspector: View {
    @ObservedObject var model: AppModel
    let node: ShelfNode
    var onError: (String?) -> Void
    var onRelocated: (URL) -> Void

    @State private var name = ""
    @State private var folder = ""
    @State private var defaults = FolderDefaults.empty

    var body: some View {
        Form {
            Section("Folder") {
                TextField("Name", text: $name)
                    .onSubmit { relocate { try model.rename(node.url, toDisplayName: name) } }
            }

            Section {
                Picker("Open", selection: $defaults.openMode) {
                    Text("Inherit").tag(OpenMode?.none)
                    Text("Normal window").tag(OpenMode?.some(.normal))
                    Text("Private window").tag(OpenMode?.some(.privateWindow))
                }
                Picker("Browser", selection: $defaults.browserBundleID) {
                    Text("Inherit").tag(String?.none)
                    ForEach(model.inventory.installedBrowsers(), id: \.bundleID) { candidate in
                        Text(candidate.displayName).tag(String?.some(candidate.bundleID))
                    }
                }
            } header: {
                Text("Defaults for this folder")
            } footer: {
                Text("Applies to everything inside, unless an entry or a nested folder says "
                     + "otherwise. Stored as \(FolderDefaults.filename) in the folder itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: defaults) { newValue in
                apply { try model.setFolderDefaults(newValue, at: node.url) }
            }

            Section("Location") {
                FolderPicker(model: model, selection: $folder, current: node.url) { destination in
                    relocate { try model.move(node.url, to: destination) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    private func load() {
        name = node.name
        defaults = model.folderDefaults(at: node.url)
        guard let root = model.rootURL else { return }
        let parent = node.url.deletingLastPathComponent().standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        folder = parent.hasPrefix(rootPath)
            ? String(parent.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            : ""
    }

    private func apply(_ work: () throws -> Void) {
        do {
            try work()
            onError(nil)
        } catch {
            onError(AppModel.describe(error))
        }
    }

    /// Renaming and moving change the file's URL, which is the selection's
    /// identity — without this the inspector would empty itself after an edit.
    private func relocate(_ work: () throws -> URL) {
        do {
            onRelocated(try work())
            onError(nil)
        } catch {
            onError(AppModel.describe(error))
        }
    }
}

// MARK: - Shared

/// Relocation is a folder picker rather than drag and drop: it is unambiguous,
/// and it does not depend on hit-testing a tree the user is also selecting in.
private struct FolderPicker: View {
    @ObservedObject var model: AppModel
    @Binding var selection: String
    /// Excluded from the choices, along with everything inside it — a folder
    /// cannot be moved into itself.
    let current: URL
    var onMove: (URL) -> Void

    var body: some View {
        Picker("Folder", selection: $selection) {
            ForEach(choices, id: \.self) { path in
                Text(path.isEmpty ? "Shelf root" : path).tag(path)
            }
        }
        .onChange(of: selection) { newValue in
            guard let destination = model.url(forFolderPath: newValue) else { return }
            onMove(destination)
        }
    }

    private var choices: [String] {
        guard let root = model.rootURL else { return [""] }
        let currentPath = current.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path

        return model.folderPaths().filter { path in
            let candidate = path.isEmpty ? rootPath : "\(rootPath)/\(path)"
            return candidate != currentPath && !candidate.hasPrefix(currentPath + "/")
        }
    }
}
