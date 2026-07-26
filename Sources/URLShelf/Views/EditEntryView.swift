import AppKit
import SwiftUI

/// Edits one entry — the only thing Finder genuinely cannot do, since the open
/// mode and browser live inside the `.webloc` plist.
///
/// Deliberately not a shelf browser: renaming, moving, and deleting stay Finder's
/// job (see ADR-0001). The window is reached from the entry itself in the menu,
/// so there is nothing to navigate.
struct EditEntryView: View {
    @ObservedObject var model: AppModel
    let fileURL: URL
    var onFinish: () -> Void

    @State private var urlText = ""
    @State private var openMode: OpenMode?
    @State private var browser: String?
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section {
                    TextField("URL", text: $urlText)
                        .onSubmit(commitURL)
                } footer: {
                    Text("Press Return to apply.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Open", selection: $openMode) {
                        Text("Inherit").tag(OpenMode?.none)
                        Text("Normal window").tag(OpenMode?.some(.normal))
                        Text("Private window").tag(OpenMode?.some(.privateWindow))
                    }
                    .onChange(of: openMode) { newValue in
                        guard loaded else { return }
                        apply { try model.updateEntry(at: fileURL, openMode: .some(newValue)) }
                    }

                    Picker("Browser", selection: $browser) {
                        Text("Inherit").tag(String?.none)
                        ForEach(model.inventory.installedBrowsers(), id: \.bundleID) { candidate in
                            Text(candidate.displayName).tag(String?.some(candidate.bundleID))
                        }
                    }
                    .onChange(of: browser) { newValue in
                        guard loaded else { return }
                        apply { try model.updateEntry(at: fileURL, browserBundleID: .some(newValue)) }
                    }
                } footer: {
                    Text("Inherit follows the folder's defaults and your settings.")
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
                // Renaming and moving are Finder's job, so the way there is one
                // click rather than a feature of its own.
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                Spacer()
                Button("Done", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let entry = try? model.entry(at: fileURL) else {
            errorMessage = "This file is not a readable web location."
            return
        }
        urlText = entry.url.absoluteString
        openMode = entry.openMode
        browser = entry.browserBundleID
        // The pickers fire onChange as they take their initial value; writing
        // the file back at that point would be a pointless save on every open.
        loaded = true
    }

    private func commitURL() {
        guard let url = WebURL.parse(urlText) else {
            errorMessage = "That is not a URL. Include the scheme, e.g. https://example.com"
            return
        }
        apply { try model.updateEntry(at: fileURL, url: url) }
    }

    private func apply(_ work: () throws -> Void) {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = AppModel.describe(error)
        }
    }
}
