import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    @State private var loginItemEnabled = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Shelf") {
                LabeledContent("Folder") {
                    HStack {
                        Text(model.config.rootPath ?? "Not set")
                            .foregroundStyle(model.config.rootPath == nil ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.head)
                        Spacer()
                        Button("Choose…", action: chooseRoot)
                    }
                }
                LabeledContent("Drop target") {
                    TextField("", text: inboxBinding, prompt: Text("Shelf root"))
                        .textFieldStyle(.roundedBorder)
                }
                Text("Folder that receives URLs dropped on the menu bar icon, "
                     + "relative to the shelf folder. Leave empty to use the shelf folder itself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu order") {
                Picker("Group", selection: groupingBinding) {
                    ForEach(ShelfGrouping.allCases, id: \.self) { grouping in
                        Text(grouping.displayName).tag(grouping)
                    }
                }
                Picker("Direction", selection: descendingBinding) {
                    Text("Ascending").tag(false)
                    Text("Descending").tag(true)
                }
                Text("Sorted by filename, so a numeric prefix (01_, 02_) orders entries "
                     + "explicitly. \"Name only\" lets a prefix order folders and entries "
                     + "against each other.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Browsers") {
                Picker("Normal entries", selection: normalBrowserBinding) {
                    Text("System Default").tag(BrowserSelection.systemDefault)
                    ForEach(model.inventory.installedBrowsers(), id: \.bundleID) { browser in
                        Text(browser.displayName).tag(BrowserSelection.bundleID(browser.bundleID))
                    }
                }

                Picker("Private entries", selection: privateBrowserBinding) {
                    Text("None").tag(String?.none)
                    ForEach(model.inventory.privateCapableBrowsers(), id: \.bundleID) { browser in
                        Text(browser.displayName).tag(String?.some(browser.bundleID))
                    }
                }

                if model.inventory.privateCapableBrowsers().isEmpty {
                    Text("No installed browser supports being opened in a private window from "
                         + "another app. Safari offers no such mechanism; Firefox, Chrome, and "
                         + "Edge do.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.config.privateBrowser == nil {
                    Text("Until a browser is chosen here, entries marked private stay disabled — "
                         + "they are never opened in the normal session instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: $loginItemEnabled)
                    .disabled(!model.loginItem.isAvailable)
                    .onChange(of: loginItemEnabled, perform: setLoginItem)
                if !model.loginItem.isAvailable {
                    Text("Available once the app is installed as a bundle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("URL Shelf \(AppInfo.version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .onAppear { loginItemEnabled = model.loginItem.isEnabled }
    }

    // MARK: - Bindings

    private var inboxBinding: Binding<String> {
        Binding(
            get: { model.config.inbox },
            set: { value in perform { try model.setInbox(value) } })
    }

    private var groupingBinding: Binding<ShelfGrouping> {
        Binding(
            get: { model.config.sort.grouping },
            set: { value in
                perform { try model.setSort(ShelfSort(
                    grouping: value, descending: model.config.sort.descending)) }
            })
    }

    private var descendingBinding: Binding<Bool> {
        Binding(
            get: { model.config.sort.descending },
            set: { value in
                perform { try model.setSort(ShelfSort(
                    grouping: model.config.sort.grouping, descending: value)) }
            })
    }

    private var normalBrowserBinding: Binding<BrowserSelection> {
        Binding(
            get: { model.config.normalBrowser },
            set: { value in perform { try model.setNormalBrowser(value) } })
    }

    private var privateBrowserBinding: Binding<String?> {
        Binding(
            get: { model.config.privateBrowser },
            set: { value in perform { try model.setPrivateBrowser(value) } })
    }

    // MARK: - Actions

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder that holds your .webloc files."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try model.setRoot(url) }
    }

    private func setLoginItem(_ enabled: Bool) {
        do {
            try model.loginItem.setEnabled(enabled)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            // Reflect what the system actually did, not what was asked for.
            loginItemEnabled = model.loginItem.isEnabled
        }
    }

    private func perform(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = AppModel.describe(error)
        }
    }
}
