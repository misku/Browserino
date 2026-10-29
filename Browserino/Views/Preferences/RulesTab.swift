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
    let name: (BrowserTarget) -> String
    /// The same names as plain text, for VoiceOver.
    let bubble: String
    let pickerText: String
    let action: () -> Void

    static let slot: CGFloat = 34
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
                                    BrowserTargetIcon(target: target, badgeSize: 12)
                                        .frame(width: 32, height: 32)
                                        .opacity(target.hasMissingProfile ? 0.4 : 1)
                                } else {
                                    Image(systemName: "questionmark.app.dashed")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 32, height: 32)
                                }

                                Text(number(target).map(String.init) ?? "?")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: Self.slot)
                        }

                        if shown.count < targets.count {
                            Text("+\(targets.count - shown.count)")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: Self.slot + 4, height: 26)
                                .background(Capsule().fill(Color.primary.opacity(0.08)))
                        }
                    }
                }
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverBubble {
            if targets.isEmpty {
                Text(bubble)
            } else {
                // Numbers right-aligned in their own column, so the names line
                // up like the rows of the Browsers tab.
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                    ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                        GridRow {
                            Text(number(target).map(String.init) ?? "?")
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)

                            Group {
                                if Bundle(url: target.app) != nil {
                                    BrowserTargetIcon(target: target, badgeSize: 8)
                                } else {
                                    Image(systemName: "questionmark.app.dashed")
                                        .resizable()
                                        .scaledToFit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 21, height: 21)

                            Text(name(target))
                        }
                    }
                }
            }
        }
        .accessibilityLabel(bubble)
        .accessibilityHint("Shows the browser list")
    }
}

/// A checkbox drawn as a button. A Toggle's binding can be written by
/// SwiftUI itself while it updates the view; a button only acts on a click,
/// so a browser is only ever added or removed by the user.
private struct BrowserCheckbox: View {
    let target: BrowserTarget
    let number: Int?
    let name: String
    let isOn: Bool
    let isInstalled: Bool
    let isHidden: Bool
    let isEnabled: Bool
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)

                Text(number.map(String.init) ?? "?")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .trailing)

                if isInstalled {
                    BrowserTargetIcon(target: target, badgeSize: 10)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }

                Text(name)
                    .lineLimit(1)
                    .foregroundStyle(isHidden || !isInstalled ? .secondary : .primary)

                if isHidden {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled || isOn ? 1 : 0.5)
        .help(help)
        .accessibilityLabel(name)
        .accessibilityValue(isOn ? "Checked" : "Unchecked")
        .accessibilityAddTraits(.isToggle)
    }
}

/// One checkbox of the browser list: a target and its number in the
/// Browsers tab, nil when it isn't there.
private struct ChooserEntry {
    let target: BrowserTarget
    let number: Int?
}

/// The checkbox grid under a row. It lists the whole Browsers tab in its
/// order, hidden browsers included (a rule may route to a browser kept out of
/// the picker), then anything the rule holds that the list doesn't.
private struct BrowserChooser: View {
    let heading: String
    /// Why the last checked box can't be unchecked, worded for its row.
    let lastOneHelp: String
    let browsers: [BrowserTarget]
    let hidden: [BrowserTarget]
    let names: [String: String]
    let targets: [BrowserTarget]
    let setTargets: ([BrowserTarget]) -> Void
    let chooseOtherApp: () -> Void

    private var offList: [BrowserTarget] {
        targets.filter { !browsers.contains($0) }
    }

    private func toggle(_ target: BrowserTarget) {
        if targets.contains(target) {
            setTargets(targets.filter { $0 != target })
        } else {
            setTargets((targets + [target]).ordered(like: browsers))
        }
    }

    private func checkbox(_ target: BrowserTarget, number: Int?) -> some View {
        let isOn = targets.contains(target)
        let isOnlyOne = isOn && targets.count == 1
        let isInstalled = Bundle(url: target.app) != nil
        let isHidden = hidden.contains(target)
        let name = isInstalled
            ? target.displayName(using: names)
            : "\(target.app.appDisplayName) (not installed)"

        return BrowserCheckbox(
            target: target,
            number: number,
            name: name,
            isOn: isOn,
            isInstalled: isInstalled,
            isHidden: isHidden,
            // Something that isn't there can only be unchecked.
            isEnabled: !isOnlyOne && (isOn || (isInstalled && number != nil)),
            help: isOnlyOne
                ? lastOneHelp
                : "\(number.map(String.init) ?? "?") · \(name)\(isHidden ? ", hidden from the picker" : "")",
            action: { toggle(target) }
        )
    }

    /// Numbers run down the first column, then down the second, so the list
    /// reads in Browsers order like the Browsers tab instead of across rows.
    private func twoColumns(_ entries: [ChooserEntry]) -> some View {
        let split = (entries.count + 1) / 2

        return HStack(alignment: .top, spacing: 16) {
            column(Array(entries.prefix(split)))
            column(Array(entries.dropFirst(split)))
        }
    }

    private func column(_ entries: [ChooserEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entries, id: \.target) { entry in
                checkbox(entry.target, number: entry.number)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            twoColumns(browsers.enumerated().map { ChooserEntry(target: $0.element, number: $0.offset + 1) })

            if !offList.isEmpty {
                Text("Not in Browsers list")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                twoColumns(offList.map { ChooserEntry(target: $0, number: nil) })
            }

            HStack(alignment: .firstTextBaseline) {
                Button("Choose Other App…", action: chooseOtherApp)
                    .help("Send these links to an app that isn't in the Browsers list")

                Spacer(minLength: 12)

                Text(
                    (targets.isEmpty
                        ? "Shows the picker with all browsers. Check browsers to choose them instead."
                        : "One browser opens links directly; two or more show the picker with only those.")
                    + (targets.contains { $0.container != nil }
                        ? " Firefox containers need the extension \"Open external links in a container\"."
                        : "")
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
                .allowsHitTesting(false)
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
    var portEnd: Int? = nil
    let targets: [BrowserTarget]
    let iconCap: Int
    let number: (BrowserTarget) -> Int?
    let name: (BrowserTarget) -> String
    let bubble: String
    let isIncognito: Bool
    let privateHelp: String
    let toggleIncognito: () -> Void
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let reset: () -> Void
    let warning: String?
    let chooser: BrowserChooser
    var moveUp: (() -> Void)? = nil
    var moveDown: (() -> Void)? = nil

    private var portHelp: String {
        guard let port else {
            return title
        }

        guard let portEnd else {
            return "\(title) on port \(String(port))"
        }

        return "\(title) on ports \(String(port)) to \(String(portEnd))"
    }

    private var titleText: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(isPattern ? .body.monospaced() : .body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            if let port {
                Text(":\(String(port))" + (portEnd.map { "-\(String($0))" } ?? ""))
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
                    .help(portHelp)
                    .accessibilityAction(named: "Move Up") { moveUp?() }
                    .accessibilityAction(named: "Move Down") { moveDown?() }
                } else {
                    Color.clear.frame(width: 24, height: 24)

                    titleText
                        .help("Links that no rule above matches")
                }

                TargetIcons(
                    targets: targets,
                    cap: iconCap,
                    number: number,
                    name: name,
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
                    .transition(.opacity)
            }
        }
        .clipped()
    }
}

/// What the rows read from the Browsers tab, decoded once per redraw:
/// @AppStorage decodes its JSON on every read, and each row asks for every
/// target's number and name several times.
private struct BrowserLookup {
    let browsers: [BrowserTarget]
    let hidden: [BrowserTarget]
    let names: [String: String]
    private let positions: [BrowserTarget: Int]

    init(browsers: [BrowserTarget], hidden: [BrowserTarget], names: [String: String]) {
        self.browsers = browsers
        self.hidden = hidden
        self.names = names
        positions = Dictionary(
            browsers.enumerated().map { ($0.element, $0.offset + 1) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    func number(of target: BrowserTarget) -> Int? {
        positions[target]
    }

    @MainActor
    func name(of target: BrowserTarget) -> String {
        guard Bundle(url: target.app) != nil else {
            return "\(target.app.appDisplayName) (not installed)"
        }

        let name = target.displayName(using: names)

        return positions[target] != nil ? name : "\(name) (not in Browsers list)"
    }

    @MainActor
    func bubble(for targets: [BrowserTarget], pickerText: String) -> String {
        guard !targets.isEmpty else {
            return pickerText
        }

        return targets
            .map { "\(number(of: $0).map(String.init) ?? "?")  \(name(of: $0))" }
            .joined(separator: "\n")
    }

    @MainActor
    func privateHelp(for targets: [BrowserTarget], isOn: Bool, subject: String) -> String {
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
    /// The row Choose Other App adds to. Kept apart from the dialog's own
    /// flag: SwiftUI clears that before it reports the choice.
    @State private var otherAppDestination: RowKey?
    @State private var otherAppPresented = false
    @State private var width: CGFloat = 660

    /// Six icons fit next to a readable pattern at the narrowest window; every
    /// extra 38pt of width shows one more.
    private var iconCap: Int {
        6 + max(0, Int((width - 660) / (TargetIcons.slot + TargetIcons.gap)))
    }

    private func update(_ id: UUID, _ change: (inout Rule) -> Void) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else {
            return
        }

        var rule = rules[index]
        change(&rule)
        rules[index] = rule
    }

    private func setTargets(_ targets: [BrowserTarget], for key: RowKey) {
        switch key {
        case .rule(let id):
            update(id) { $0.targets = targets }
        case .allOtherLinks:
            catchallTargets = targets
        }
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

    private func ruleRow(
        _ rule: Rule,
        index: Int,
        count: Int,
        handle: ReorderHandle,
        isUnreachable: Bool,
        lookup: BrowserLookup
    ) -> some View {
        RuleRow(
            handle: handle.addingMenu([
                .action("Edit Rule…") { editing = rule },
                .action("Show Picker…", isEnabled: !rule.showsPicker) { pendingReset = .rule(rule.id) },
                .action("Delete Rule…") { pendingDelete = rule },
            ]),
            onEdit: { editing = rule },
            title: rule.regex,
            isPattern: true,
            port: rule.port,
            portEnd: rule.portEnd,
            targets: rule.targets,
            iconCap: iconCap,
            number: lookup.number(of:),
            name: lookup.name(of:),
            bubble: lookup.bubble(
                for: rule.targets,
                pickerText: "Shows the picker with all browsers, as if no rule matched."
            ),
            isIncognito: rule.isIncognito,
            privateHelp: lookup.privateHelp(for: rule.targets, isOn: rule.isIncognito, subject: "Matching links"),
            toggleIncognito: { update(rule.id) { $0.isIncognito.toggle() } },
            isExpanded: expanded == .rule(rule.id),
            toggleExpanded: { toggle(.rule(rule.id)) },
            reset: { pendingReset = .rule(rule.id) },
            warning: isUnreachable
                ? "Never used: a rule above matches every link. Use All Other Links instead."
                : nil,
            chooser: BrowserChooser(
                heading: "Open matching links in",
                lastOneHelp: "A rule needs at least one browser. Use Reset to show the picker instead.",
                browsers: lookup.browsers,
                hidden: lookup.hidden,
                names: lookup.names,
                targets: rule.targets,
                setTargets: { setTargets($0, for: .rule(rule.id)) },
                chooseOtherApp: {
                    otherAppDestination = .rule(rule.id)
                    otherAppPresented = true
                }
            ),
            moveUp: index > 0 ? { move(from: index, to: index - 1) } : nil,
            moveDown: index < count - 1 ? { move(from: index, to: index + 1) } : nil
        )
    }

    private func allOtherLinksRow(lookup: BrowserLookup, isUnreachable: Bool) -> some View {
        RuleRow(
            handle: nil,
            onEdit: nil,
            title: "All Other Links",
            isPattern: false,
            port: nil,
            targets: catchallTargets,
            iconCap: iconCap,
            number: lookup.number(of:),
            name: lookup.name(of:),
            bubble: lookup.bubble(for: catchallTargets, pickerText: "Shows the picker with all browsers."),
            isIncognito: catchallIncognito,
            privateHelp: lookup.privateHelp(for: catchallTargets, isOn: catchallIncognito, subject: "Other links"),
            toggleIncognito: { catchallIncognito.toggle() },
            isExpanded: expanded == .allOtherLinks,
            toggleExpanded: { toggle(.allOtherLinks) },
            reset: { pendingReset = .allOtherLinks },
            warning: isUnreachable ? "Never used: a rule above matches every link." : nil,
            chooser: BrowserChooser(
                heading: "Open other links in",
                lastOneHelp: "Keep at least one browser here, or use Reset to show the picker for all other links.",
                browsers: lookup.browsers,
                hidden: lookup.hidden,
                names: lookup.names,
                targets: catchallTargets,
                setTargets: { setTargets($0, for: .allOtherLinks) },
                chooseOtherApp: {
                    otherAppDestination = .allOtherLinks
                    otherAppPresented = true
                }
            )
        )
    }

    private func browserCount(_ count: Int) -> String {
        count == 1 ? "1 browser" : "\(count) browsers"
    }

    private var resetTitle: String {
        pendingReset == .allOtherLinks
            ? "Show the picker for all other links?"
            : "Show the picker for this rule?"
    }

    private var resetMessage: String {
        switch pendingReset {
        case .allOtherLinks:
            return "Links no rule matches will show the picker with all browsers. Your choice of \(browserCount(catchallTargets.count)) will be cleared."
        case .rule(let id):
            let rule = rules.first { $0.id == id }
            return "Links matching \(rule?.regex ?? "this rule") will show the picker with all browsers, as if no rule existed. Your choice of \(browserCount(rule?.targets.count ?? 0)) will be cleared."
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
        let allRules = rules
        let lookup = BrowserLookup(browsers: browsers, hidden: hiddenBrowsers, names: names)
        // Rules after the first one that takes every link never run.
        let firstMatchingEveryLink = allRules.firstIndex { $0.matchesEveryLink }

        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsCard {
                        if allRules.isEmpty {
                            Text("No rules yet. Click + to send matching links to chosen browsers.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                        } else {
                            ReorderableStack(
                                items: allRules,
                                id: { $0.id },
                                onDragStarted: { index in
                                    // Closing an open list above the dragged row
                                    // would pull the row out from under the
                                    // pointer, so only a list at or below it
                                    // closes.
                                    if case .rule(let id) = expanded,
                                       let open = allRules.firstIndex(where: { $0.id == id }),
                                       open < index {
                                        return
                                    }
                                    expanded = nil
                                },
                                move: { from, to in rules.move(from: from, to: to) }
                            ) { rule, index, handle in
                                VStack(spacing: 0) {
                                    if index > 0 {
                                        RowDivider()
                                    }

                                    ruleRow(
                                        rule,
                                        index: index,
                                        count: allRules.count,
                                        handle: handle,
                                        isUnreachable: firstMatchingEveryLink.map { index > $0 } ?? false,
                                        lookup: lookup
                                    )
                                }
                            }
                        }
                    }

                    SettingsCard {
                        allOtherLinksRow(lookup: lookup, isUnreachable: firstMatchingEveryLink != nil)
                    }
                }
            }
            .scrollEdgeEffectDisabledCompat()

            ListBottomBar(hint: "Drag a rule by its handle to reorder. The first matching rule wins, and All Other Links takes the rest.") {
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
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        }
        // One importer for every row's Choose Other App, so a result can only
        // ever reach the row that asked for it.
        .fileImporter(
            isPresented: $otherAppPresented,
            allowedContentTypes: [.application]
        ) { result in
            defer {
                otherAppDestination = nil
            }

            guard let key = otherAppDestination, case .success(let url) = result else {
                return
            }

            let current: [BrowserTarget]
            switch key {
            case .rule(let id):
                current = rules.first { $0.id == id }?.targets ?? []
            case .allOtherLinks:
                current = catchallTargets
            }

            let target = BrowserTarget(app: url)
            if !current.contains(target) {
                setTargets((current + [target]).ordered(like: browsers), for: key)
            }
        }
        .sheet(isPresented: $addPresented) {
            RuleForm(
                original: nil,
                onCancel: { addPresented = false },
                onSave: { regex, port, portEnd in
                    let rule = Rule(regex: regex, targets: [], port: port, portEnd: portEnd)
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
                onSave: { regex, port, portEnd in
                    update(rule.id) {
                        $0.regex = regex
                        $0.port = port
                        $0.portEnd = portEnd
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
