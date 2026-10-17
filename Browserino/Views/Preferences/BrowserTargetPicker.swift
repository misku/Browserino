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

    /// macOS menus drop item icons, so two profiles called "misku" in different
    /// browsers would read the same. Those get their browser's name added.
    private func menuTitle(for target: BrowserTarget) -> String {
        let title = target.displayName(using: names)
        let sameTitle = browsers.filter { $0.displayName(using: names) == title }

        guard sameTitle.count > 1, target.profile != nil else {
            return title
        }

        let browser = Bundle(url: target.app)?.appDisplayName ?? target.app.appDisplayName

        return "\(title) (\(browser))"
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
                        Text(menuTitle(for: target))
                    } icon: {
                        Image(nsImage: target.smallIcon)
                    }
                }
            }

            if !browsers.isEmpty {
                Divider()
            }

            Button("Other App…") {
                otherPresented = true
            }
        } label: {
            if let selection {
                // A pop-up button lays its label out at its own size, so the icon
                // has to arrive already sized.
                HStack {
                    Image(nsImage: selection.smallIcon)

                    Text(
                        Bundle(url: selection.app) == nil
                            ? "\(selection.app.appDisplayName) (not installed)"
                            : menuTitle(for: selection)
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
