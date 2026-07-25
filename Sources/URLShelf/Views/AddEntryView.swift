import AppKit
import SwiftUI

/// Adding an entry creates data; the settings window changes how the app
/// behaves. They are separate windows so that the frequent action — filing a URL
/// — is one click from the menu rather than buried in configuration.
struct AddEntryView: View {
    @ObservedObject var model: AppModel
    var onFinish: () -> Void

    @State private var urlText = ""
    @State private var name = ""
    @State private var folder = ""
    @State private var isPrivate = false
    @State private var browserOverride: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("URL", text: $urlText, prompt: Text("https://example.com"))
                    TextField("Name", text: $name, prompt: Text("Taken from the address"))
                }

                Section {
                    Picker("Folder", selection: $folder) {
                        ForEach(model.folderPaths(), id: \.self) { path in
                            Text(path.isEmpty ? "Shelf root" : path).tag(path)
                        }
                    }
                    Toggle("Open in a private window", isOn: $isPrivate)
                    Picker("Browser", selection: $browserOverride) {
                        Text("Inherit").tag(String?.none)
                        ForEach(browserChoices, id: \.bundleID) { browser in
                            Text(browser.displayName).tag(String?.some(browser.bundleID))
                        }
                    }
                } footer: {
                    Text(footerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: onFinish)
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty
                              || model.rootURL == nil)
            }
            .padding(12)
        }
        .onAppear(perform: prefillFromClipboard)
        .onChange(of: isPrivate) { _ in
            // A browser that cannot open privately is not a valid override for a
            // private entry, so drop it rather than build an impossible plan.
            if isPrivate, let id = browserOverride,
               BrowserCatalog.capability(forBundleID: id)?.supportsPrivate != true {
                browserOverride = nil
            }
        }
    }

    private var browserChoices: [BrowserCapability] {
        isPrivate ? model.inventory.privateCapableBrowsers() : model.inventory.installedBrowsers()
    }

    private var footerText: String {
        if model.rootURL == nil {
            return "Choose a shelf folder in Settings first."
        }
        return "Leave Browser on Inherit to follow the folder's defaults and your settings."
    }

    /// The URL to file is almost always the one just copied.
    private func prefillFromClipboard() {
        guard urlText.isEmpty,
              let text = NSPasteboard.general.string(forType: .string),
              let url = WebURL.parse(text)
        else { return }
        urlText = url.absoluteString
    }

    private func add() {
        let trimmed = urlText.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: trimmed), url.scheme != nil else {
            errorMessage = "That is not a URL. Include the scheme, e.g. https://example.com"
            return
        }
        guard let destination = model.url(forFolderPath: folder) else {
            errorMessage = "Choose a shelf folder in Settings first."
            return
        }

        do {
            try model.addEntry(
                url: url,
                name: name,
                in: destination,
                openMode: isPrivate ? .privateWindow : nil,
                browserBundleID: browserOverride)
            onFinish()
        } catch {
            errorMessage = AppModel.describe(error)
        }
    }
}
