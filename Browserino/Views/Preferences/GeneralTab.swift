//
//  GeneralTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI
import UniformTypeIdentifiers
import ServiceManagement

struct SettingsDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    // Serialized on the way in: [String: Any] cannot cross a Sendable boundary.
    private var data: Data

    init(settings: [String: Any] = [:]) {
        data = (try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents,
              let object = try? JSONSerialization.jsonObject(with: contents),
              object is [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}

/// The settings a backup carries, and how each is stored. Window places, the
/// last pane and folder grants belong to this Mac and stay out of it.
enum SettingsBackup {
    enum Kind {
        /// A list or table stored as JSON text; the closure says whether
        /// this build can read all of it.
        case json(@Sendable (String) -> Bool)
        case flag
        case text
    }

    private static func readable<T: Decodable>(_ type: T.Type) -> @Sendable (String) -> Bool {
        { (try? JSONDecoder().decode(T.self, from: Data($0.utf8))) != nil }
    }

    static var kinds: [String: Kind] {
        [
            "rules": .json(readable([Rule].self)),
            "browsers": .json(readable([BrowserTarget].self)),
            "hiddenBrowsers": .json(readable([BrowserTarget].self)),
            "catchallTargets": .json(readable([BrowserTarget].self)),
            "apps": .json(readable([App].self)),
            "directories": .json(readable([Directory].self)),
            "shortcuts": .json(readable([String: String].self)),
            "browserNames": .json(readable([String: String].self)),
            "privateArgs": .json(readable([String: String].self)),
            "catchallIncognito": .flag,
            "apps_autoOpen": .flag,
            "apps_atTop": .flag,
            "showInMenuBar": .flag,
            "copy_closeAfterCopy": .flag,
            "copy_alternativeShortcut": .flag,
            "ruleTestUrls": .text,
        ]
    }
}

struct GeneralTab: View {
    @State private var isDefault = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showingExportPicker = false
    @State private var showingImportPicker = false
    @State private var exportDocument = SettingsDocument()
    @State private var pendingImport: URL?
    @State private var confirmReset = false
    @State private var status: String?
    @AppStorage("copy_closeAfterCopy") private var closeAfterCopy: Bool = false
    @AppStorage("copy_alternativeShortcut") private var alternativeShortcut: Bool = false
    @AppStorage("showInMenuBar") private var showInMenuBar: Bool = true
    @AppStorage("apps_atTop") private var appsAtTop: Bool = true
    @AppStorage("apps_autoOpen") private var autoOpenApps: Bool = false
    
    func defaultBrowser() -> String? {
        guard let browserUrl = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https:")!) else {
            return nil
        }
        
        return Bundle(url: browserUrl)?.bundleIdentifier
    }

    /// Says what happened next to the buttons for a few seconds, instead of in a
    /// console nobody reads.
    private func show(_ message: String) {
        status = message

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if status == message {
                status = nil
            }
        }
    }
    
    func exportSettings() {
        let defaults = UserDefaults.standard
        var appSettings: [String: Any] = [:]

        for key in SettingsBackup.kinds.keys {
            if let value = defaults.object(forKey: key) {
                appSettings[key] = value
            }
        }

        exportDocument = SettingsDocument(settings: appSettings)
        showingExportPicker = true
    }

    /// Checks every setting in the file before writing any, so a bad file
    /// changes nothing. UserDefaults aborts the app on a value it can't store,
    /// such as null, so nothing unchecked reaches it.
    func importSettings(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            show("That file isn't a Browserino settings file.")
            return
        }

        var values: [String: Any] = [:]

        for (key, kind) in SettingsBackup.kinds {
            guard let value = settings[key] else {
                continue
            }

            switch kind {
            case .json(let isReadable):
                guard let text = value as? String, isReadable(text) else {
                    show("Nothing was imported: \(key) holds a value Browserino can't read.")
                    return
                }

                // Rules from an older backup get their ids now, or edits
                // to them would find no rule to change.
                values[key] = key == "rules" ? Rule.addingMissingIDs(toStored: text) ?? text : text
            case .flag:
                guard let flag = value as? Bool else {
                    show("Nothing was imported: \(key) should be on or off.")
                    return
                }

                values[key] = flag
            case .text:
                guard let text = value as? String else {
                    show("Nothing was imported: \(key) should be text.")
                    return
                }

                values[key] = text
            }
        }

        guard !values.isEmpty else {
            show("That file holds no Browserino settings.")
            return
        }

        // Replace, not merge: a setting the backup doesn't have goes back to
        // its default, so nothing from before keeps routing links.
        let defaults = UserDefaults.standard
        for key in SettingsBackup.kinds.keys {
            if let value = values[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        show("Settings imported.")
    }

    func resetSettings() {
        let defaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        dictionary.keys.forEach { key in
            defaults.removeObject(forKey: key)
        }

        show("All settings were reset.")
    }
    
    var body: some View {
        Form {
            Section {
                if isDefault {
                    Label("Browserino is your default browser", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    LabeledContent("Browserino is not your default browser") {
                        Button("Make Default") {
                            NSWorkspace.shared.setDefaultApplication(
                                at: Bundle.main.bundleURL,
                                toOpenURLsWithScheme: "http"
                            ) { _ in
                                Task { @MainActor in
                                    isDefault = defaultBrowser() == Bundle.main.bundleIdentifier
                                }
                            }
                        }
                        .help("Make Browserino your default web browser")
                    }
                }
            } header: {
                Text("Default Browser")
            } footer: {
                if !isDefault {
                    Text("Browserino has to be the default browser to choose where links open.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Picker") {
                Toggle("Show apps above browsers", isOn: $appsAtTop)

                Toggle(isOn: $autoOpenApps) {
                    Text("Open app links without asking")
                    Text("When an app in the Apps tab matches the link's host, it opens directly.")
                }

                Toggle("Close the picker after copying the link", isOn: $closeAfterCopy)

                Picker("Copy link shortcut", selection: $alternativeShortcut) {
                    Text("⌥⌘C").tag(false)
                    Text("⌘C").tag(true)
                }
            }

            Section("Startup") {
                Toggle(isOn: $showInMenuBar) {
                    Text("Show in menu bar")
                    Text("When hidden, open Browserino from Applications to get back here.")
                }

                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                LabeledContent("Back up") {
                    HStack {
                        Button("Export…") {
                            exportSettings()
                        }
                        .help("Save all settings to a file")

                        Button("Import…") {
                            showingImportPicker = true
                        }
                        .help("Replace your settings with ones from a file")
                    }
                }

                LabeledContent("Reset all settings") {
                    Button("Reset…", role: .destructive) {
                        confirmReset = true
                    }
                    .help("Erase every Browserino setting")
                }
            } header: {
                Text("Settings")
            } footer: {
                if let status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .toggleStyle(.switch)
        .onAppear {
            isDefault = defaultBrowser() == Bundle.main.bundleIdentifier
        }
        .fileExporter(
            isPresented: $showingExportPicker,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "browserino-settings"
        ) { result in
            switch result {
            case .success(let url):
                show("Settings saved to \(url.lastPathComponent).")
            case .failure(let error):
                show("Export failed: \(error.localizedDescription)")
            }
        }
        .fileImporter(
            isPresented: $showingImportPicker,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                pendingImport = urls.first
            }
        }
        .confirmationDialog(
            "Replace your settings with \(pendingImport?.lastPathComponent ?? "this file")?",
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )
        ) {
            Button("Replace Settings", role: .destructive) {
                if let url = pendingImport {
                    importSettings(from: url)
                }
                pendingImport = nil
            }
        } message: {
            Text("Rules, apps, browser order, names, shortcuts and private flags are replaced by the file's. Settings the file doesn't have go back to their defaults.")
        }
        .alert("Reset all Browserino settings?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset All Settings", role: .destructive) {
                resetSettings()
            }
        } message: {
            Text("Rules, apps, browser order, names, shortcuts and private flags are erased. This can't be undone.")
        }
    }
}

#Preview {
    PreferencesView()
}
