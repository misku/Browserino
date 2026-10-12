//
//  BrowserTargetPicker.swift
//  Browserino
//

import SwiftUI

/// Picks the browser a rule or site mapping opens in, from the list already set up
/// under Browsers — profiles included, so a profile needs no second control.
/// Anything not in that list is still reachable through "Other Application".
struct BrowserTargetPicker: View {
    @Binding var app: URL?
    @Binding var profile: String?

    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("browserNames") private var names: [String: String] = [:]
    @State private var otherPresented = false

    private var selection: BrowserTarget? {
        app.map { BrowserTarget(app: $0, profile: profile) }
    }

    var body: some View {
        Menu {
            ForEach(Array(browsers.enumerated()), id: \.offset) { _, target in
                Button {
                    app = target.app
                    profile = target.profile
                } label: {
                    // Two browsers can share a profile name, so the icon tells them apart.
                    Label {
                        Text(target.displayName(using: names))
                    } icon: {
                        Image(nsImage: target.smallIcon)
                    }
                }
            }

            if !browsers.isEmpty {
                Divider()
            }

            Button("Other Application…") {
                otherPresented = true
            }
        } label: {
            if let selection {
                HStack {
                    BrowserTargetIcon(target: selection, badgeSize: 8)
                        .frame(width: 16, height: 16)

                    Text(
                        Bundle(url: selection.app) == nil
                            ? "\(selection.app.appDisplayName) (not installed)"
                            : selection.displayName(using: names)
                    )
                }
            } else {
                Text("Choose a browser")
            }
        }
        .fileImporter(
            isPresented: $otherPresented,
            allowedContentTypes: [.application]
        ) {
            if case .success(let url) = $0 {
                app = url
                // The previous app's profile directory means nothing here.
                profile = nil
            }
        }
    }
}
