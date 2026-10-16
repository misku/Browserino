//
//  RulesTab.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

struct AddRule: View {
    @State private var addPresented = false
    
    var body: some View {
        HStack {
            Image(systemName: "plus")
                .font(
                    .system(size: 14)
                )
                .opacity(0)
            
            Text("Add a new rule by typing regex and selecting an app.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
                .frame(width: 16)
            
            Button(action: {
                addPresented.toggle()
            }) {
                Text("Add new rule")
            }
            .sheet(isPresented: $addPresented) {
                NewRuleForm(
                    isPresented: $addPresented
                )
            }
        }
    }
}

/// The right side of a rule row: "Brave or Firefox" with their icons, or the
/// full picker when Default catchall names no browser.
struct RuleTargets: View {
    var targets: [BrowserTarget]
    var isIncognito: Bool

    @AppStorage("browserNames") private var names: [String: String] = [:]

    var body: some View {
        if targets.isEmpty {
            Text("All browsers (picker)")
                .font(
                    .system(size: 14)
                )
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 0) {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                    let installed = Bundle(url: target.app) != nil

                    if index > 0 {
                        Text(" or ")
                    }

                    Text(installed
                         ? target.displayName(using: names)
                         : "\(target.app.appDisplayName) (not installed)")
                        .foregroundStyle(
                            !installed || target.hasMissingProfile ? .secondary : .primary
                        )
                }
            }
            .font(
                .system(size: 14)
            )
        }

        if isIncognito {
            Image(systemName: "eyeglasses")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help("Opens in a private window")
        }

        if !targets.isEmpty {
            Spacer()
                .frame(width: 8)

            HStack(spacing: 4) {
                ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                    if Bundle(url: target.app) != nil {
                        BrowserTargetIcon(target: target)
                            .frame(width: 32, height: 32)
                    } else {
                        Image(systemName: "questionmark.app.dashed")
                            .font(.system(size: 24))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                    }
                }
            }
        }
    }
}

struct RuleItem: View {
    @Binding var rule: Rule
    /// An earlier rule already takes every link this one could see.
    var isUnreachable: Bool = false
    @State private var editPresented = false
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button(action: {
                    editPresented.toggle()
                }) {
                    Label(rule.regex, systemImage: "pencil")
                        .font(
                            .system(size: 14)
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                if let port = rule.port {
                    Text(":\(port)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                RuleTargets(targets: rule.targets, isIncognito: rule.isIncognito)
            }

            if isUnreachable {
                Text("Never used: a rule above matches every link. Use Default catchall instead.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .sheet(isPresented: $editPresented) {
            EditRuleForm(
                rule: $rule,
                isPresented: $editPresented
            )
        }
    }
}

/// Always the last row: it takes every link no rule matched, so it can't be
/// dragged above a rule or deleted.
struct CatchallItem: View {
    @AppStorage("catchallTargets") private var catchallTargets: [BrowserTarget] = []
    @AppStorage("catchallIncognito") private var catchallIncognito: Bool = false
    @State private var editPresented = false

    var body: some View {
        HStack {
            Button(action: {
                editPresented.toggle()
            }) {
                Label("Default catchall", systemImage: "pencil")
                    .font(
                        .system(size: 14)
                    )
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)

            Spacer()

            RuleTargets(targets: catchallTargets, isIncognito: catchallIncognito)
        }
        .padding(10)
        .sheet(isPresented: $editPresented) {
            CatchallForm(
                isPresented: $editPresented
            )
        }
    }
}

struct RulesTab: View {
    @AppStorage("rules") private var rules: [Rule] = []

    private func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
    }

    var body: some View {
        // Rules after the first one that takes every link never run.
        let firstMatchingEveryLink = rules.firstIndex { $0.matchesEveryLink }

        VStack (alignment: .leading) {
            List {
                AddRule()

                ForEach(Array($rules.enumerated()), id: \.offset) { offset, rule in
                    RuleItem(
                        rule: rule,
                        isUnreachable: firstMatchingEveryLink.map { offset > $0 } ?? false
                    )
                }
                .onMove(perform: move)

                CatchallItem()
            }
            .scrollContentBackground(.hidden)

            Text("Drag to reorder. The first matching rule wins, and Default catchall takes the rest.")
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.5))
                .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
    }
}

#Preview {
    RulesTab()
}
