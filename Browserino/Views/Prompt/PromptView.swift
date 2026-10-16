//
//  PromptView.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import AppKit
import SwiftUI

struct PromptView: View {
    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [BrowserTarget] = []
    @AppStorage("apps") private var apps: [App] = []
    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]

    @AppStorage("copy_closeAfterCopy") private var closeAfterCopy: Bool = false
    @AppStorage("copy_alternativeShortcut") private var alternativeShortcut: Bool = false
    @AppStorage("apps_atTop") private var appsAtTop: Bool = true

    let urls: [URL]
    /// Set when a rule or Default catchall names several browsers: the picker
    /// then lists exactly these, in this order, and no Apps.
    var targets: [BrowserTarget]? = nil
    /// The rule's private window setting, used by Return and by a click.
    var isIncognito: Bool = false

    @State private var opacityAnimation = 0.0
    @State private var selected = 0
    @FocusState private var focused: Bool

    // Return, the arrows and the shortcuts all index appsForUrls and
    // visibleBrowsers, so narrowing both here keeps them in step with the rows.
    var appsForUrls: [App] {
        if targets != nil {
            return []
        }

        return urls.flatMap { url in
            return apps.filter { app in
                url.matchesHost(app.host)
            }
        }
        .filter {
            !browsers.contains($0.target)
        }
        // A row whose bundle no longer resolves renders as nothing, so excluding it
        // here keeps the keyboard selection indices in step with what is on screen.
        .filter {
            Bundle(url: $0.app) != nil
        }
    }

    var visibleBrowsers: [BrowserTarget] {
        if let targets {
            return targets
        }

        return browsers.filter {
            !hiddenBrowsers.contains($0) && Bundle(url: $0.app) != nil
        }
    }

    func shortcut(for target: BrowserTarget) -> String? {
        Bundle(url: target.app)?.bundleIdentifier.flatMap {
            shortcuts[target.shortcutKey(bundleIdentifier: $0)]
        }
    }

    func openUrlsInApp(app: App) {
        BrowserUtil.openURL(
            app.urlsToOpen(urls),
            target: app.target,
            isIncognito: false
        )
    }

    /// Return and Shift-Return act on the highlighted row. An empty list has no
    /// such row, so they do nothing rather than index past the end.
    private func openSelected(isIncognito: Bool) {
        let apps = appsForUrls
        let browsers = visibleBrowsers
        let appIndex = selected - (appsAtTop ? 0 : browsers.count)
        let browserIndex = selected - (appsAtTop ? apps.count : 0)

        if apps.indices.contains(appIndex) {
            openUrlsInApp(app: apps[appIndex])
        } else if browsers.indices.contains(browserIndex) {
            BrowserUtil.openURL(urls, target: browsers[browserIndex], isIncognito: isIncognito)
        }
    }

    var body: some View {
        VStack {
            ScrollViewReader { scrollViewProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if !appsForUrls.isEmpty && appsAtTop {
                            ForEach(Array(appsForUrls.enumerated()), id: \.offset) { index, app in
                                PromptItem(
                                    target: app.target,
                                    title: app.target.displayName,
                                    shortcut: shortcut(for: app.target)
                                ) {
                                    openUrlsInApp(app: app)
                                }
                                .id(index)
                                .buttonStyle(
                                    SelectButtonStyle(
                                        selected: selected == index
                                    )
                                )
                            }

                            Divider()
                        }
                        
                        ForEach(Array(visibleBrowsers.enumerated()), id: \.offset) {
                            index, browser in
                            PromptItem(
                                target: browser,
                                title: browser.displayName,
                                shortcut: shortcut(for: browser)
                            ) {
                                BrowserUtil.openURL(
                                    urls,
                                    target: browser,
                                    isIncognito: isIncognito || NSEvent.modifierFlags.contains(.shift)
                                )
                            }
                            .id(index + (appsAtTop ? appsForUrls.count : 0))
                            .buttonStyle(
                                SelectButtonStyle(
                                    selected: selected == index + (appsAtTop ? appsForUrls.count : 0)
                                )
                            )
                        }

                        if !appsForUrls.isEmpty && !appsAtTop {
                            Divider()

                            ForEach(Array(appsForUrls.enumerated()), id: \.offset) { index, app in
                                PromptItem(
                                    target: app.target,
                                    title: app.target.displayName,
                                    shortcut: shortcut(for: app.target)
                                ) {
                                    openUrlsInApp(app: app)
                                }
                                .id(visibleBrowsers.count + index)
                                .buttonStyle(
                                    SelectButtonStyle(
                                        selected: selected == visibleBrowsers.count + index
                                    )
                                )
                            }
                        }
                    }
                }
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onMoveCommand { command in
                    if command == .up {
                        selected = max(0, selected - 1)
                        scrollViewProxy.scrollTo(selected, anchor: .center)
                    } else if command == .down {
                        selected = max(0, min(visibleBrowsers.count + appsForUrls.count - 1, selected + 1))
                        scrollViewProxy.scrollTo(selected, anchor: .center)
                    }
                }
                .background {
                    Button(action: {
                        openSelected(isIncognito: isIncognito)
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.defaultAction)

                    Button(action: {
                        openSelected(isIncognito: true)
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.return, modifiers: [.shift])

                    Button(action: {
                        NSApplication.shared.keyWindow?.close()
                    }) {}
                    .opacity(0)
                    .keyboardShortcut(.cancelAction)
                }
                .onAppear {
                    focused.toggle()
                    withAnimation(.interactiveSpring(duration: 0.3)) {
                        opacityAnimation = 1
                    }
                }
                .scrollEdgeEffectDisabledCompat()
            }

            Divider()

            if let host = urls.first?.host() {
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.declareTypes([.string], owner: nil)
                    pasteboard.setString(urls.first?.absoluteString ?? "", forType: .string)

                    if closeAfterCopy {
                        NSApplication.shared.keyWindow?.close()
                    }
                }) {
                    Text(
                        host
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(
                    KeyEquivalent("c"),
                    modifiers: alternativeShortcut ? [.command] : [.command, .option]
                )
                .toolTip(urls.first?.absoluteString ?? "")
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity
        )
        .background(BlurredView())
        .opacity(opacityAnimation)
        .edgesIgnoringSafeArea(.all)
    }
}

#Preview {
    PromptView(urls: [])
}
