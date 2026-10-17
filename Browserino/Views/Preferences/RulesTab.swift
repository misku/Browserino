//
//  RulesTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

/// The row whose browser list is open. One at a time: a list of twenty
/// profiles is tall, and two open turn the tab into a wall.
private enum RowKey: Hashable {
    case rule(UUID)
    case allOtherLinks
}

/// A rule's browsers as icons, each with its number from the Browsers tab
/// underneath. One hover box covers the group and names them all at once.
private struct TargetIcons: View {
    let targets: [BrowserTarget]
    /// How many slots fit; the last becomes "+N" when there are more.
    let cap: Int
    let number: (BrowserTarget) -> Int?
    let bubble: String
    let pickerText: String
    let action: () -> Void

    static let slot: CGFloat = 22
    static let gap: CGFloat = 4

    private var shown: [BrowserTarget] {
        targets.count <= cap ? targets : Array(targets.prefix(max(cap - 1, 1)))
    }

    var body: some View {
        Button(action: action) {
            Group {
                if targets.isEmpty {
                    Text(pickerText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    HStack(spacing: Self.gap) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, target in
                            VStack(spacing: 1) {
                                if Bundle(url: target.app) != nil {
                                    BrowserTargetIcon(target: target, badgeSize: 8)
                                        .frame(width: 20, height: 20)
                                        .opacity(target.hasMissingProfile ? 0.4 : 1)
                                } else {
                                    Image(systemName: "questionmark.app.dashed")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20, height: 20)
                                }

                                Text(number(target).map(String.init) ?? "?")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: Self.slot)
                        }

                        if shown.count < targets.count {
                            Text("+\(targets.count - shown.count)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: Self.slot + 8, height: 20)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverBubble(bubble)
        .accessibilityLabel(bubble)
        .accessibilityHint("Shows the browser list")
    }
}

/// The checkbox grid under a row. It lists the whole Browsers tab in its
/// order, hidden browsers included (a rule may route to a browser kept out of
/// the picker), then anything the rule holds that the list doesn't.
private struct BrowserChooser: View {
    let heading: String
    let browsers: [BrowserTarget]
    let hidden: [BrowserTarget]
    let names: [String: String]
    @Binding var targets: [BrowserTarget]

    @State private var otherPresented = false

    private var offList: [BrowserTarget] {
        targets.filter { !browsers.contains($0) }
    }

    private func add(_ target: BrowserTarget) {
        if !targets.contains(target) {
            targets = (targets + [target]).ordered(like: browsers)
        }
    }

    private func binding(for target: BrowserTarget) -> Binding<Bool> {
        Binding(
            get: { targets.contains(target) },
            set: { isOn in
                if isOn {
                    add(target)
                } else {
                    targets.removeAll { $0 == target }
                }
            }
        )
    }

    private func cell(_ target: BrowserTarget, number: Int?) -> some View {
        let isChecked = targets.contains(target)
        let isOnlyOne = isChecked && targets.count == 1
        let isInstalled = Bundle(url: target.app) != nil
        let isHidden = hidden.contains(target)
        let name = isInstalled
            ? target.displayName(using: names)
            : "\(target.app.appDisplayName) (not installed)"

        return Toggle(isOn: binding(for: target)) {
            HStack(spacing: 6) {
                Text(number.map(String.init) ?? "?")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)

                if isInstalled {
                    BrowserTargetIcon(target: target, badgeSize: 7)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }

                Text(name)
                    .lineLimit(1)
                    .foregroundStyle(isHidden || !isInstalled ? .secondary : .primary)

                if isHidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
        // Something that isn't there can only be unchecked.
        .disabled(isOnlyOne || (!isChecked && (!isInstalled || number == nil)))
        .help(
            isOnlyOne
                ? "A rule needs at least one browser. Use Reset to show the picker instead."
                : "\(number.map(String.init) ?? "?") · \(name)\(isHidden ? ", hidden from the picker" : "")"
        )
    }

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 180), spacing: 16, alignment: .leading)]

        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(Array(browsers.enumerated()), id: \.offset) { index, browser in
                    cell(browser, number: index + 1)
                }
            }

            if !offList.isEmpty {
                Text("Not in Browsers list")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(offList.enumerated()), id: \.offset) { _, target in
                        cell(target, number: nil)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Button("Choose Other App…") {
                    otherPresented = true
                }
                .help("Send these links to an app that isn't in the Browsers list")

                Spacer(minLength: 12)

                Text(
                    targets.isEmpty
                        ? "Shows the picker with all browsers. Check browsers to choose them instead."
                        : "One browser opens links directly; two or more show the picker with only those."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
            .padding(.top, 4)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .fileImporter(isPresented: $otherPresented, allowedContentTypes: [.application]) { result in
            if case .success(let url) = result {
                add(BrowserTarget(app: url))
            }
        }
    }
}

/// One line of the Rules tab: a rule, or All Other Links, which has no handle,
/// no pattern to edit and no port.
private struct RuleRow: View {
    let handle: ReorderHandle?
    let onEdit: (() -> Void)?
    let title: String
    let isPattern: Bool
    let port: Int?
    let targets: [BrowserTarget]
    let iconCap: Int
    let number: (BrowserTarget) -> Int?
    let bubble: String
    let isIncognito: Bool
    let privateHelp: String
    let toggleIncognito: () -> Void
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let reset: () -> Void
    let warning: String?
    let chooser: BrowserChooser

    private var titleText: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(isPattern ? .body.monospaced() : .body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let port {
                Text(":\(String(port))")
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let handle {
                    handle
                } else {
                    Color.clear.frame(width: 16, height: 28)
                }

                if let onEdit {
                    IconButton(systemImage: "pencil", help: "Edit pattern, port and test links", action: onEdit)

                    Button(action: onEdit) {
                        titleText
                    }
                    .buttonStyle(.plain)
                    .help(port.map { "\(title) on port \(String($0))" } ?? title)
                } else {
                    Color.clear.frame(width: 24, height: 24)

                    titleText
                        .help("Links that no rule above matches")
                }

                TargetIcons(
                    targets: targets,
                    cap: iconCap,
                    number: number,
                    bubble: bubble,
                    pickerText: "All browsers (picker)",
                    action: toggleExpanded
                )

                IconButton(
                    systemImage: "hand.raised",
                    help: privateHelp,
                    label: "Private window",
                    isOn: isIncognito,
                    action: toggleIncognito
                )

                IconButton(
                    systemImage: "arrow.counterclockwise",
                    help: targets.isEmpty
                        ? "Already shows the picker with all browsers"
                        : "Show the picker with all browsers instead of the chosen ones",
                    label: "Show picker",
                    action: reset
                )
                .disabled(targets.isEmpty)

                IconButton(
                    systemImage: "chevron.down",
                    help: isExpanded ? "Hide the browser list" : "Choose browsers",
                    label: isExpanded ? "Hide browsers" : "Choose browsers",
                    action: toggleExpanded
                )
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12 + 16 + 8 + 24 + 8)
                    .padding(.trailing, 12)
                    .padding(.bottom, 8)
            }

            if isExpanded {
                chooser
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipped()
    }
}

struct RulesTab: View {
    @AppStorage("rules") private var rules: [Rule] = []
    @AppStorage("browsers") private var browsers: [BrowserTarget] = []
    @AppStorage("hiddenBrowsers") private var hiddenBrowsers: [BrowserTarget] = []
    @AppStorage("browserNames") private var names: [String: String] = [:]
    @AppStorage("catchallTargets") private var catchallTargets: [BrowserTarget] = []
    @AppStorage("catchallIncognito") private var catchallIncognito: Bool = false

    @State private var expanded: RowKey?
    @State private var addPresented = false
    @State private var editing: Rule?
    @State private var pendingReset: RowKey?
    @State private var pendingDelete: Rule?
    @State private var width: CGFloat = 660

    /// Six icons fit next to a readable pattern at the narrowest window; every
    /// extra 26pt of width shows one more.
    private var iconCap: Int {
        6 + max(0, Int((width - 660) / 26))
    }

    private func number(of target: BrowserTarget) -> Int? {
        browsers.firstIndex(of: target).map { $0 + 1 }
    }

    private func name(of target: BrowserTarget) -> String {
        guard Bundle(url: target.app) != nil else {
            return "\(target.app.appDisplayName) (not installed)"
        }

        let name = target.displayName(using: names)

        return browsers.contains(target) ? name : "\(name) (not in Browsers list)"
    }

    private func bubble(for targets: [BrowserTarget]) -> String {
        guard !targets.isEmpty else {
            return "Shows the picker with all browsers, as if no rule matched."
        }

        return targets
            .map { "\(number(of: $0).map(String.init) ?? "?")  \(name(of: $0))" }
            .joined(separator: "\n")
    }

    private func privateHelp(for targets: [BrowserTarget], isOn: Bool, subject: String) -> String {
        let summary = isOn
            ? "\(subject) open in a private window. Click to turn it off."
            : "Click to open \(subject.lowercased()) in a private window."

        let unsupported = targets
            .filter { Bundle(url: $0.app) != nil && BrowserUtil.privateArgument(for: $0) == nil }
            .map { $0.displayName(using: names) }

        guard isOn, !unsupported.isEmpty else {
            return summary
        }

        return summary + "\n" + unsupported.joined(separator: ", ")
            + " can't be asked for a private window and opens normally."
    }

    private func update(_ id: UUID, _ change: (inout Rule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }

        var rule = rules[index]
        change(&rule)
        rules[index] = rule
    }

    private func targets(of id: UUID) -> Binding<[BrowserTarget]> {
        Binding(
            get: { rules.first { $0.id == id }?.targets ?? [] },
            set: { newTargets in update(id) { $0.targets = newTargets } }
        )
    }

    private func toggle(_ key: RowKey) {
        withAnimation(.snappy(duration: 0.25)) {
            expanded = expanded == key ? nil : key
        }
    }

    private func move(from: Int, to: Int) {
        withAnimation(.snappy(duration: 0.2)) {
            rules.move(from: from, to: to)
        }
    }

    private func ruleRow(_ rule: Rule, index: Int, handle: ReorderHandle, isUnreachable: Bool) -> some View {
        RuleRow(
            handle: handle,
            onEdit: { editing = rule },
            title: rule.regex,
            isPattern: true,
            port: rule.port,
            targets: rule.targets,
            iconCap: iconCap,
            number: number(of:),
            bubble: bubble(for: rule.targets),
            isIncognito: rule.isIncognito,
            privateHelp: privateHelp(for: rule.targets, isOn: rule.isIncognito, subject: "Matching links"),
            toggleIncognito: { update(rule.id) { $0.isIncognito.toggle() } },
            isExpanded: expanded == .rule(rule.id),
            toggleExpanded: { toggle(.rule(rule.id)) },
            reset: { pendingReset = .rule(rule.id) },
            warning: isUnreachable
                ? "Never used: a rule above matches every link. Use All Other Links instead."
                : nil,
            chooser: BrowserChooser(
                heading: "Open matching links in",
                browsers: browsers,
                hidden: hiddenBrowsers,
                names: names,
                targets: targets(of: rule.id)
            )
        )
        .contextMenu {
            Button("Edit Rule…") { editing = rule }

            Divider()

            Button("Move Up") { move(from: index, to: index - 1) }
                .disabled(index == 0)
            Button("Move Down") { move(from: index, to: index + 1) }
                .disabled(index == rules.count - 1)
            Button("Move to Top") { move(from: index, to: 0) }
                .disabled(index == 0)

            Divider()

            Button("Show Picker…") { pendingReset = .rule(rule.id) }
                .disabled(rule.showsPicker)
            Button("Delete Rule…", role: .destructive) { pendingDelete = rule }
        }
        .accessibilityAction(named: "Move Up") {
            if index > 0 {
                move(from: index, to: index - 1)
            }
        }
        .accessibilityAction(named: "Move Down") {
            if index < rules.count - 1 {
                move(from: index, to: index + 1)
            }
        }
    }

    private var allOtherLinksRow: some View {
        RuleRow(
            handle: nil,
            onEdit: nil,
            title: "All Other Links",
            isPattern: false,
            port: nil,
            targets: catchallTargets,
            iconCap: iconCap,
            number: number(of:),
            bubble: catchallTargets.isEmpty
                ? "Shows the picker with all browsers."
                : bubble(for: catchallTargets),
            isIncognito: catchallIncognito,
            privateHelp: privateHelp(for: catchallTargets, isOn: catchallIncognito, subject: "Other links"),
            toggleIncognito: { catchallIncognito.toggle() },
            isExpanded: expanded == .allOtherLinks,
            toggleExpanded: { toggle(.allOtherLinks) },
            reset: { pendingReset = .allOtherLinks },
            warning: rules.contains { $0.matchesEveryLink }
                ? "Never used: a rule above matches every link."
                : nil,
            chooser: BrowserChooser(
                heading: "Open other links in",
                browsers: browsers,
                hidden: hiddenBrowsers,
                names: names,
                targets: $catchallTargets
            )
        )
    }

    private var resetTitle: String {
        pendingReset == .allOtherLinks
            ? "Show the picker for all other links?"
            : "Show the picker for this rule?"
    }

    private var resetMessage: String {
        switch pendingReset {
        case .allOtherLinks:
            return "Links no rule matches will show the picker with all browsers. Your choice of \(catchallTargets.count) will be cleared."
        case .rule(let id):
            let rule = rules.first { $0.id == id }
            return "Links matching \(rule?.regex ?? "this rule") will show the picker with all browsers, as if no rule existed. Your choice of \(rule?.targets.count ?? 0) will be cleared."
        case nil:
            return ""
        }
    }

    private func performReset() {
        switch pendingReset {
        case .allOtherLinks:
            catchallTargets = []
        case .rule(let id):
            update(id) { $0.targets = [] }
        case nil:
            break
        }

        pendingReset = nil
    }

    var body: some View {
        // Rules after the first one that takes every link never run.
        let firstMatchingEveryLink = rules.firstIndex { $0.matchesEveryLink }

        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        if rules.isEmpty {
                            Text("No rules yet. Click + to send matching links to chosen browsers.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        } else {
                            ReorderableStack(
                                items: rules,
                                id: { $0.id },
                                onDragStarted: { expanded = nil },
                                move: { from, to in rules.move(from: from, to: to) }
                            ) { rule, index, handle in
                                VStack(spacing: 0) {
                                    if index > 0 {
                                        RowDivider()
                                    }

                                    ruleRow(
                                        rule,
                                        index: index,
                                        handle: handle,
                                        isUnreachable: firstMatchingEveryLink.map { index > $0 } ?? false
                                    )
                                }
                            }
                        }
                    }

                    SettingsCard {
                        allOtherLinksRow
                    }
                }
            }
            .scrollEdgeEffectDisabledCompat()

            ListBottomBar(hint: "Drag to reorder. The first matching rule wins, and All Other Links takes the rest.") {
                IconButton(systemImage: "plus", help: "Add a rule (Command-N)") {
                    addPresented = true
                }
            }
        }
        .padding(20)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { width = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        width = newWidth
                    }
            }
        }
        .background {
            Button("Add Rule") {
                addPresented = true
            }
            .keyboardShortcut("n")
            .opacity(0)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $addPresented) {
            RuleForm(
                original: nil,
                onCancel: { addPresented = false },
                onSave: { regex, port in
                    let rule = Rule(regex: regex, targets: [], port: port)
                    rules.insert(rule, at: 0)
                    addPresented = false

                    // New rules start on the picker; open the list so choosing
                    // browsers is the obvious next step.
                    withAnimation(.snappy(duration: 0.25)) {
                        expanded = .rule(rule.id)
                    }
                }
            )
        }
        .sheet(item: $editing) { rule in
            RuleForm(
                original: rule,
                onCancel: { editing = nil },
                onSave: { regex, port in
                    update(rule.id) {
                        $0.regex = regex
                        $0.port = port
                    }
                    editing = nil
                },
                onDelete: {
                    rules.removeAll { $0.id == rule.id }
                    editing = nil
                }
            )
        }
        .alert(
            resetTitle,
            isPresented: Binding(
                get: { pendingReset != nil },
                set: { if !$0 { pendingReset = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Show Picker", role: .destructive) {
                performReset()
            }
        } message: {
            Text(resetMessage)
        }
        .alert(
            "Delete this rule?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Delete Rule", role: .destructive) {
                if let rule = pendingDelete {
                    rules.removeAll { $0.id == rule.id }
                }
                pendingDelete = nil
            }
        } message: {
            Text("Links matching \(pendingDelete?.regex ?? "it") go to the next matching rule, or to All Other Links.")
        }
    }
}

#Preview {
    RulesTab()
}
