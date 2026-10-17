//  BrowserSearchLocationsTab.swift
//  Browserino
//
//  Created by byt3m4st3r.
//

import AppKit
import SwiftUI

struct Directory: Codable, Hashable {
    var directoryPath: String
}

/// The folders searched for browsers. Rarely touched, so it lives behind a
/// button next to Rescan instead of taking a whole tab, and it rescans on its
/// own after every change.
struct SearchLocationsSheet: View {
    @Binding var isPresented: Bool
    let onChange: () -> Void

    @AppStorage("directories") private var directories: [Directory] = []
    @State private var explorerPresented = false

    private static let applications = "/Applications"

    /// NSWorkspace builds a new image on every call, and rows redraw often.
    @MainActor private static var icons: [String: NSImage] = [:]

    @MainActor private static func icon(for path: String) -> NSImage {
        if let cached = icons[path] {
            return cached
        }

        let image = NSWorkspace.shared.icon(forFile: path)
        icons[path] = image

        return image
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Locations")
                .font(.headline)

            Text("Browserino looks for browsers in these folders.")
                .font(.callout)
                .foregroundStyle(.secondary)

            SettingsCard {
                ForEach(Array(directories.enumerated()), id: \.element) { index, directory in
                    if index > 0 {
                        RowDivider(leadingInset: 40)
                    }

                    HStack(spacing: 10) {
                        Image(nsImage: Self.icon(for: directory.directoryPath))
                            .resizable()
                            .frame(width: 18, height: 18)

                        Text(directory.directoryPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(directory.directoryPath)

                        IconButton(
                            systemImage: "minus",
                            help: directory.directoryPath == Self.applications
                                ? "Applications is always searched"
                                : "Stop searching this folder",
                            action: {
                                directories.removeAll { $0 == directory }
                                onChange()
                            }
                        )
                        .disabled(directory.directoryPath == Self.applications)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            HStack {
                IconButton(
                    systemImage: "plus",
                    help: "Add a folder to search. In the Finder dialog, Shift-Command-G enters a path."
                ) {
                    explorerPresented = true
                }

                Spacer()

                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .fileImporter(
            isPresented: $explorerPresented,
            allowedContentTypes: [.directory]
        ) { result in
            if case let .success(dir) = result {
                let newDirectory = Directory(directoryPath: dir.path)
                if !directories.contains(newDirectory) {
                    directories.append(newDirectory)
                    onChange()
                }
            }
        }
        .onAppear {
            if directories.isEmpty {
                directories.append(Directory(directoryPath: Self.applications))
            }
        }
    }
}
