//
//  EditAppForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

/// Adds or edits an App. It works on a copy, so Cancel leaves the stored App
/// exactly as it was.
struct AppForm: View {
    let original: App?
    let onCancel: () -> Void
    let onSave: (App) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var host: String = ""
    @State private var appURL: URL?
    @State private var profile: String?
    @State private var schemeOverride: String = ""
    @State private var confirmDelete = false

    /// "" for every link, nil while the text is not a host.
    private var normalizedHost: String? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)

        if trimmed.isEmpty {
            return ""
        }

        let url = if trimmed.starts(with: /https?:\/\//) {
            trimmed
        } else {
            "http://" + trimmed
        }

        return URL(string: url)?.host()
    }

    private var canSave: Bool {
        normalizedHost != nil && appURL != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Host", text: $host, prompt: Text("example.com"))

                    LabeledContent("Open in") {
                        BrowserTargetPicker(app: $appURL, profile: $profile)
                    }
                } header: {
                    Text(original == nil ? "New App" : "Edit App")
                        .font(.headline)
                } footer: {
                    Text("Leave the host empty to offer the app for every link.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Replace scheme", text: $schemeOverride, prompt: Text("zoommtg"))
                        .font(.body.monospaced())
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("For apps that register their own scheme: the link opens with it instead of http or https.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if onDelete != nil {
                    Button("Delete App…", role: .destructive) {
                        confirmDelete = true
                    }
                }

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(original == nil ? "Add App" : "Save") {
                    guard let host = normalizedHost, let appURL else {
                        return
                    }

                    onSave(
                        App(
                            host: host,
                            schemeOverride: schemeOverride.trimmingCharacters(in: .whitespaces),
                            app: appURL,
                            profile: profile
                        )
                    )
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 480, height: 360)
        .confirmationDialog(
            "Delete this app?",
            isPresented: $confirmDelete
        ) {
            Button("Delete App", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Links to \(host.isEmpty ? "any host" : host) will no longer offer it.")
        }
        .onAppear {
            host = original?.host ?? ""
            appURL = original?.app
            profile = original?.profile
            schemeOverride = original?.schemeOverride ?? ""
        }
    }
}

#Preview {
    AppForm(
        original: App(
            host: "mm.2gis.one",
            schemeOverride: "",
            app: URL(string: "file:///Applications/Mattermost.app")!
        ),
        onCancel: {},
        onSave: { _ in }
    )
}
