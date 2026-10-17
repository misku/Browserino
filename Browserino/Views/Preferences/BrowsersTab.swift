//
//  BrowsersTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

/// Column widths shared by the header and the rows, so they line up.
private enum BrowserColumns {
    static let spacing: CGFloat = 12
    static let handle: CGFloat = 16
    static let number: CGFloat = 22
    static let icon: CGFloat = 24
    static let flag: CGFloat = 170
    static let key: CGFloat = 64
    static let show: CGFloat = 24
}

private struct BrowserRow: View {
    let browser: BrowserTarget
    let number: Int
    let handle: ReorderHandle
    /// The row that edits this browser's private flag, when it is another one.
    /// The flag belongs to the browser, so every profile row shares it.
    let flagRow: Int?
    let isHidden: Bool
    @Binding var name: String
    @Binding var privateArg: String
    let toggleHidden: () -> Void
    let remove: () -> Void
    /// Reordering for VoiceOver, which can't drag the handle.
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?

    @State private var nameHovered = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let bundle = Bundle(url: browser.app)

        HStack(spacing: BrowserColumns.spacing) {
            handle

            Text("\(number)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: BrowserColumns.number, alignment: .trailing)

            if let bundle {
                BrowserTargetIcon(target: browser, badgeSize: 10)
                    .frame(width: BrowserColumns.icon, height: BrowserColumns.icon)
                    .opacity(isHidden ? 0.45 : 1)

                TextField("Name", text: $name, prompt: Text(browser.defaultName))
                    .textFieldStyle(.plain)
                    .foregroundStyle(isHidden ? .secondary : .primary)
                    .focused($nameFocused)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(nameHovered || nameFocused ? 0.06 : 0))
                    }
                    .onHover { nameHovered = $0 }
                    .frame(minWidth: 140, maxWidth: .infinity, alignment: .leading)
                    .help(
                        browser.container == nil
                            ? "Click to rename. Clear the name to use the default."
                            : "A Firefox container. Links open through the extension \"Open external links in a container\". Click to rename."
                    )

                if let flagRow {
                    Text("Same as row \(flagRow)")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .frame(width: BrowserColumns.flag, alignment: .leading)
                        .help("The private flag belongs to the browser, so every profile row shares it.")
                } else {
                    let knownFlag = BrowserUtil.defaultPrivateArgument(forAppAt: browser.app)
                    let isSafari = bundle.bundleIdentifier?.lowercased().hasPrefix("com.apple.safari") == true

                    TextField(
                        "Private flag",
                        text: $privateArg,
                        prompt: Text(isSafari ? "Not supported" : knownFlag ?? "Private flag")
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .frame(width: BrowserColumns.flag)
                    .disabled(isSafari)
                    .help(
                        isSafari
                            ? "Safari can't be asked to open a private window."
                            : "Passed to the browser to open a private window. Leave empty to use the known flag."
                    )
                }

                if let browserId = bundle.bundleIdentifier {
                    ShortcutButton(shortcutKey: browser.shortcutKey(bundleIdentifier: browserId))
                        .frame(width: BrowserColumns.key)
                } else {
                    Color.clear.frame(width: BrowserColumns.key, height: 1)
                }

                IconButton(
                    systemImage: isHidden ? "eye.slash" : "eye",
                    help: isHidden ? "Hidden from the picker. Click to show it." : "Shown in the picker. Click to hide it.",
                    label: isHidden ? "Show in picker" : "Hide from picker",
                    action: toggleHidden
                )
                .frame(width: BrowserColumns.show)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
                    .frame(width: BrowserColumns.icon, height: BrowserColumns.icon)

                Text("\(browser.app.appDisplayName) (not installed)")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                IconButton(
                    systemImage: "minus",
                    help: "Remove this browser from the list",
                    action: remove
                )
                .frame(width: BrowserColumns.show)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityAction(named: "Move Up") { moveUp?() }
        .accessibilityAction(named: "Move Down") { moveDown?() }
    }
}

struct BrowsersTab: View {
    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [BrowserTarget] = []
    @AppStorage("privateArgs") private var privateArgs: [String: String] = [:]
    @AppStorage("browserNames") private var names: [String: String] = [:]

    @State private var locationsPresented = false
    @State private var hasScanned = false

    private func privateArg(for key: String) -> Binding<String> {
        return .init(
            get: { self.privateArgs[key, default: ""] },
            set: { self.privateArgs[key] = $0 })
    }

    /// The field holds the name in use, so an unrenamed row reads normally rather
    /// than as a grey placeholder. Clearing it, or typing the default back, stores
    /// nothing. The text is stored as typed, so a space between two words
    /// survives until the second word arrives; displayName trims it on use.
    private func name(for browser: BrowserTarget, key: String) -> Binding<String> {
        return .init(
            get: { self.names[key] ?? browser.defaultName },
            set: {
                let name = $0.trimmingCharacters(in: .whitespaces)
                self.names[key] = name.isEmpty || name == browser.defaultName ? nil : $0
            })
    }

    /// Offer the grant only where it could actually help: a Chromium browser whose
    /// profiles we have not been able to read yet. Profile rows have to qualify
    /// too. When a grant stops working the browser is still shown as the profile
    /// rows it was stored as, so requiring a plain row here would leave the user
    /// with no way to ask again.
    /// The same goes for a Firefox browser whose containers can't be read.
    private func needsProfileAccess(_ target: BrowserTarget) -> Bool {
        (ChromiumProfileService.userDataDirectory(forAppAt: target.app) != nil
            && ChromiumProfileService.profiles(forAppAt: target.app) == nil)
            || (FirefoxContainerService.dataDirectory(forAppAt: target.app) != nil
                && FirefoxContainerService.containers(forAppAt: target.app) == nil)
    }

    /// One banner per browser, not per profile row.
    private var appsNeedingAccess: [URL] {
        var seen = Set<URL>()
        return browsers.filter(needsProfileAccess).map(\.app).filter { seen.insert($0).inserted }
    }

    /// Firefox browsers that have container rows, once each.
    private var appsWithContainers: [URL] {
        var seen = Set<URL>()
        return browsers.filter { $0.container != nil }.map(\.app).filter { seen.insert($0).inserted }
    }

    private func appName(_ app: URL) -> String {
        Bundle(url: app)?.appDisplayName ?? app.appDisplayName
    }

    private func rescan() {
        let scanned = BrowserUtil.loadBrowsers(oldBrowsers: browsers)

        // Writing an unchanged list would still redraw every row.
        if scanned != browsers {
            browsers = scanned
        }
    }

    /// What every row needs from the stored lists, read once per redraw:
    /// @AppStorage decodes its JSON on each read.
    private struct Snapshot {
        let count: Int
        let hidden: Set<BrowserTarget>
        /// Index of each browser's first row, which edits its private flag.
        let firstRowOfApp: [String: Int]
    }

    private func row(_ browser: BrowserTarget, index: Int, handle: ReorderHandle, snapshot: Snapshot) -> some View {
        let bundleId = Bundle(url: browser.app)?.bundleIdentifier ?? ""
        let firstOfApp = snapshot.firstRowOfApp[browser.app.standardizedFileURL.path] ?? index

        return BrowserRow(
            browser: browser,
            number: index + 1,
            handle: handle,
            flagRow: firstOfApp == index ? nil : firstOfApp + 1,
            isHidden: snapshot.hidden.contains(browser),
            name: name(for: browser, key: browser.shortcutKey(bundleIdentifier: bundleId)),
            privateArg: privateArg(for: bundleId),
            toggleHidden: {
                if let index = hiddenBrowsers.firstIndex(of: browser) {
                    hiddenBrowsers.remove(at: index)
                } else {
                    hiddenBrowsers.append(browser)
                }
            },
            remove: {
                browsers.removeAll { $0 == browser }
                hiddenBrowsers.removeAll { $0 == browser }
            },
            moveUp: index > 0 ? { browsers.move(from: index, to: index - 1) } : nil,
            moveDown: index < snapshot.count - 1 ? { browsers.move(from: index, to: index + 1) } : nil
        )
    }

    var body: some View {
        let list = browsers
        let snapshot = Snapshot(
            count: list.count,
            hidden: Set(hiddenBrowsers),
            firstRowOfApp: list.enumerated().reduce(into: [:]) { first, entry in
                let path = entry.element.app.standardizedFileURL.path
                if first[path] == nil {
                    first[path] = entry.offset
                }
            }
        )

        VStack(alignment: .leading, spacing: 12) {
            ForEach(appsNeedingAccess, id: \.self) { app in
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)

                    let isFirefox = FirefoxContainerService.dataDirectory(forAppAt: app) != nil

                    Text("\(appName(app))'s \(isFirefox ? "containers" : "profiles") can't be read yet.")

                    Spacer()

                    Button("Allow Access…") {
                        let granted = isFirefox
                            ? FirefoxContainerService.requestAccess(forAppAt: app)
                            : ChromiumProfileService.requestAccess(forAppAt: app)

                        if granted {
                            rescan()
                        }
                    }
                    .help("macOS keeps a browser's data private until you choose its folder once.")
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                }
            }

            // Firefox can't open a container from outside on its own; the
            // extension can. Say so wherever container rows exist, and confirm
            // once it is installed.
            ForEach(appsWithContainers, id: \.self) { app in
                let isInstalled = FirefoxContainerService.hasContainerExtension(forAppAt: app) == true

                HStack(spacing: 10) {
                    Image(systemName: isInstalled ? "checkmark.circle.fill" : "puzzlepiece.extension")
                        .font(.system(size: 18))
                        .foregroundStyle(isInstalled ? Color.green : Color.secondary)

                    Text(
                        isInstalled
                            ? "\(appName(app)) containers open through the extension \"Open external links in a container\", which is installed."
                            : "\(appName(app)) containers need the free extension \"Open external links in a container\". Without it, links sent to a container don't open."
                    )
                    .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if !isInstalled {
                        Button("Get Extension…") {
                            NSWorkspace.shared.open(
                                [FirefoxContainerService.extensionPage],
                                withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()
                            )
                        }
                        .help("Open the extension's page in \(appName(app))")
                    }
                }
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(isInstalled ? 0.03 : 0.05))
                }
            }

            HStack(spacing: BrowserColumns.spacing) {
                Color.clear.frame(width: BrowserColumns.handle, height: 1)
                Text("#")
                    .frame(width: BrowserColumns.number, alignment: .trailing)
                Color.clear.frame(width: BrowserColumns.icon, height: 1)
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 6)
                Text("Private flag")
                    .frame(width: BrowserColumns.flag, alignment: .leading)
                Text("Key")
                    .frame(width: BrowserColumns.key)
                Text("Show")
                    .frame(width: BrowserColumns.show + 8)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)

            ScrollView {
                if list.isEmpty {
                    Text("No browsers found. Click Rescan, or add a folder under Search Locations.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else {
                    SettingsCard {
                        ReorderableStack(
                            items: list,
                            id: { $0 },
                            move: { from, to in browsers.move(from: from, to: to) }
                        ) { browser, index, handle in
                            VStack(spacing: 0) {
                                if index > 0 {
                                    RowDivider(leadingInset: 40)
                                }

                                row(browser, index: index, handle: handle, snapshot: snapshot)
                            }
                        }
                    }
                }
            }
            .scrollEdgeEffectDisabledCompat()

            ListBottomBar(hint: "Drag to set the picker order.") {
                IconButton(
                    systemImage: "arrow.clockwise",
                    help: "Scan again for installed browsers and profiles",
                    action: rescan
                )

                Button("Search Locations…") {
                    locationsPresented = true
                }
                .help("Choose the folders Browserino searches for browsers")
            }
        }
        .padding(20)
        .onAppear {
            // Once per Settings window: the merge keeps the user's order and is
            // idempotent, so this picks up profiles added since the last visit
            // without waiting for an explicit Rescan, but switching tabs
            // doesn't repeat the scan.
            if !hasScanned {
                hasScanned = true
                rescan()
            }
        }
        .sheet(isPresented: $locationsPresented) {
            SearchLocationsSheet(isPresented: $locationsPresented, onChange: rescan)
        }
    }
}

#Preview {
    BrowsersTab()
}
