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

struct RuleItem: View {
    @Binding var rule: Rule
    @AppStorage("browserNames") private var names: [String: String] = [:]
    @State private var editPresented = false
    
    var body: some View {
        let bundle = Bundle(url: rule.app)

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
            
            
            Text(bundle == nil
                 ? "\(rule.app.appDisplayName) (not installed)"
                 : rule.target.displayName(using: names))
                .font(
                    .system(size: 14)
                )
                .foregroundStyle(
                    bundle == nil || rule.target.hasMissingProfile ? .secondary : .primary
                )

            if rule.isIncognito {
                Image(systemName: "eyeglasses")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .help("Opens in a private window")
            }

            
            Spacer()
                .frame(width: 8)
            
            if bundle != nil {
                BrowserTargetIcon(target: rule.target)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "questionmark.app.dashed")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
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

struct RulesTab: View {
    @AppStorage("rules") private var rules: [Rule] = []

    private func move(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
    }

    var body: some View {
        VStack (alignment: .leading) {
            List {
                AddRule()

                ForEach(Array($rules.enumerated()), id: \.offset) { offset, rule in
                    RuleItem(
                        rule: rule
                    )
                }
                .onMove(perform: move)
            }
            .scrollContentBackground(.hidden)

            Text("Drag to reorder. The first matching rule wins.")
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
