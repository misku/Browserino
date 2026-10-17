//
//  BrowserTargetPicker.swift
//  Browserino
//

import SwiftUI

/// One row of BrowserTargetList.
private struct BrowserListRow: View {
    let target: BrowserTarget
    let number: Int?
    let name: String
    let isSelected: Bool
    let isHidden: Bool
    let select: () -> Void

    @State private var isHovered = false

    var body: some View {
        let isInstalled = Bundle(url: target.app) != nil

        Button(action: select) {
            HStack(spacing: 10) {
                Text(number.map(String.init) ?? "?")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)

                if isInstalled {
                    BrowserTargetIcon(target: target, badgeSize: 12)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                }

                Text(name)
                    .lineLimit(1)
                    .foregroundStyle(isHidden || !isInstalled ? .secondary : .primary)

                if isHidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .help("Hidden from the picker")
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        isSelected ? Color.accentColor.opacity(0.15)
                            : Color.primary.opacity(isHovered ? 0.05 : 0)
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Picks the browser an App opens in, from the list set up under Browsers,
/// profiles included, in that list's order and with its numbers. A list rather
/// than a menu: menus drop the icons and avatars that tell same-named profiles
/// apart, and a long menu is hard to scan. Anything not in the list is still
/// reachable through Other App.
struct BrowserTargetList: View {
    @Binding var selection: BrowserTarget?

    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [BrowserTarget] = []
    @AppStorage("browserNames") private var names: [String: String] = [:]
    @State private var otherPresented = false

    /// Two Chrome profiles can both be called "misku". Their numbers already
    /// differ; the browser and profile folder make the names differ too.
    /// `holders` maps each name to the browsers using it, built once per redraw.
    private func name(for target: BrowserTarget, holders: [String: [BrowserTarget]]) -> String {
        guard Bundle(url: target.app) != nil else {
            return "\(target.app.appDisplayName) (not installed)"
        }

        let name = target.displayName(using: names)
        let others = (holders[name] ?? []).filter { $0 != target }

        guard !others.isEmpty, let directory = target.profile else {
            return name
        }

        let browser = Bundle(url: target.app)?.appDisplayName ?? target.app.appDisplayName

        return others.contains { $0.app == target.app }
            ? "\(name) (\(browser), \(directory))"
            : "\(name) (\(browser))"
    }

    private func row(_ target: BrowserTarget, number: Int?, holders: [String: [BrowserTarget]]) -> some View {
        BrowserListRow(
            target: target,
            number: number,
            name: name(for: target, holders: holders),
            isSelected: target == selection,
            isHidden: hiddenBrowsers.contains(target),
            select: {
                selection = target
            }
        )
        .id(target)
    }

    var body: some View {
        let holders = Dictionary(grouping: browsers) { $0.displayName(using: names) }

        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(browsers.enumerated()), id: \.element) { index, target in
                            row(target, number: index + 1, holders: holders)
                        }

                        // An app chosen through Other App stays visible and selected.
                        if let selection, !browsers.contains(selection) {
                            row(selection, number: nil, holders: holders)
                        }
                    }
                    .padding(6)
                }
                .onAppear {
                    if let selection {
                        proxy.scrollTo(selection, anchor: .center)
                    }
                }
            }

            Divider()

            HStack {
                Button("Other App…") {
                    otherPresented = true
                }
                .help("Open these links in an app that isn't in the Browsers list")

                Spacer(minLength: 12)

                Text(selection.map { name(for: $0, holders: holders) } ?? "Choose a browser")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(8)
        }
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
                .allowsHitTesting(false)
        }
        .fileImporter(
            isPresented: $otherPresented,
            allowedContentTypes: [.application]
        ) {
            if case .success(let url) = $0 {
                // A plain app: the previous profile or container means nothing here.
                selection = BrowserTarget(app: url)
            }
        }
    }
}
