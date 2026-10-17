//
//  AppsTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct App: Codable, Hashable {
    var host: String
    var schemeOverride: String
    var app: URL
    var profile: String?

    var target: BrowserTarget {
        BrowserTarget(app: app, profile: profile)
    }

    /// The links with this app's scheme override applied.
    func urlsToOpen(_ urls: [URL]) -> [URL] {
        if schemeOverride.isEmpty {
            return urls
        }

        return urls.map {
            let url = NSURLComponents.init(
                url: $0,
                resolvingAgainstBaseURL: true
            )
            url!.scheme = schemeOverride

            return url!.url!
        }
    }
}

private struct AppRow: View {
    let app: App
    let edit: () -> Void

    @AppStorage("browserNames") private var names: [String: String] = [:]

    var body: some View {
        let bundle = Bundle(url: app.app)

        HStack(spacing: 10) {
            IconButton(systemImage: "pencil", help: "Edit host, app and scheme", action: edit)

            Button(action: edit) {
                Text(app.host.isEmpty ? "All links" : app.host)
                    .foregroundStyle(app.host.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)

            if bundle != nil {
                BrowserTargetIcon(target: app.target, badgeSize: 8)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }

            Text(bundle == nil
                 ? "\(app.app.appDisplayName) (not installed)"
                 : app.target.displayName(using: names))
                .foregroundStyle(
                    bundle == nil || app.target.hasMissingProfile ? .secondary : .primary
                )
                .lineLimit(1)

            if !app.schemeOverride.isEmpty {
                Text("\(app.schemeOverride):")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .help("Opens links with the \(app.schemeOverride): scheme")
            }

            if let browserId = bundle?.bundleIdentifier {
                ShortcutButton(
                    shortcutKey: app.target.shortcutKey(bundleIdentifier: browserId)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The App being edited, with its place in the list.
private struct EditingApp: Identifiable {
    let id: Int
    let app: App
}

struct AppsTab: View {
    @AppStorage("apps") private var apps: [App] = []

    @State private var addPresented = false
    @State private var editing: EditingApp?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                if apps.isEmpty {
                    Text("No apps yet. Click + to open a host's links in an app, such as zoom.us in Zoom.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    SettingsCard {
                        ForEach(Array(apps.enumerated()), id: \.offset) { index, app in
                            if index > 0 {
                                RowDivider(leadingInset: 46)
                            }

                            AppRow(app: app) {
                                editing = EditingApp(id: index, app: app)
                            }
                        }
                    }
                }
            }
            .scrollEdgeEffectDisabledCompat()

            ListBottomBar(hint: "A matching app joins the picker, or opens directly if set in General.") {
                IconButton(systemImage: "plus", help: "Add an app for a host") {
                    addPresented = true
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $addPresented) {
            AppForm(
                original: nil,
                onCancel: { addPresented = false },
                onSave: {
                    apps.append($0)
                    addPresented = false
                }
            )
        }
        // Driven by the item itself, so the sheet keeps its content while it
        // animates away instead of going blank.
        .sheet(item: $editing) { item in
            AppForm(
                original: item.app,
                onCancel: { editing = nil },
                onSave: { app in
                    if apps.indices.contains(item.id) {
                        apps[item.id] = app
                    }
                    editing = nil
                },
                onDelete: {
                    if apps.indices.contains(item.id) {
                        apps.remove(at: item.id)
                    }
                    editing = nil
                }
            )
        }
    }
}

#Preview {
    AppsTab()
}
