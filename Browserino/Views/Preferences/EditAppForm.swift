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
    @State private var isLoaded = false

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

    /// A caption over a field, the way the rest of the sheet labels things.
    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "New App" : "Edit App")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                label("Host")

                TextField("Host", text: $host, prompt: Text("example.com"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()

                Text("Leave it empty to offer the app for every link.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("Open in")

                BrowserTargetList(app: $appURL, profile: $profile)
                    .frame(maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                label("Replace scheme")

                TextField("Replace scheme", text: $schemeOverride, prompt: Text("zoommtg"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .labelsHidden()

                Text("For apps that register their own scheme: the link opens with it instead of http or https.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            .padding(.top, 4)
        }
        .padding(20)
        // Fits the smallest Settings window; the browser list takes up the
        // difference.
        .frame(width: 500, height: 480)
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
            // Once: appear can fire again while the sheet is presented, and
            // must not throw away what the user typed.
            guard !isLoaded else {
                return
            }

            isLoaded = true
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
