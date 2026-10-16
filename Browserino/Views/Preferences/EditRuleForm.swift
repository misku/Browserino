//
//  EditRuleForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

struct EditRuleForm: View {
    @Binding var rule: Rule
    @Binding var isPresented: Bool
    
    @AppStorage("rules") private var rules: [Rule] = []
    
    var body: some View {
        RuleForm(
            rule: rule,
            onCancel: {
                isPresented.toggle()
            },
            onSave: {
                rule = $0
                isPresented.toggle()
            },
            onDelete: {
                rules.removeAll {
                    $0 == rule
                }
                isPresented.toggle()
            }
        )
    }
}

struct NewRuleForm: View {
    @Binding var isPresented: Bool
    
    @AppStorage("rules") private var rules: [Rule] = []
    
    var body: some View {
        RuleForm(
            rule: nil,
            onCancel: {
                isPresented.toggle()
            },
            onSave: {
                rules.append($0)
                isPresented.toggle()
            },
            onDelete: {
                isPresented.toggle()
            }
        )
    }
}

/// Default catchall is stored as two settings rather than as a rule, so it can
/// never be dragged, deleted or matched by a regex. It reuses the rule form
/// without the fields that only make sense for a rule.
struct CatchallForm: View {
    @Binding var isPresented: Bool

    @AppStorage("catchallTargets") private var catchallTargets: [BrowserTarget] = []
    @AppStorage("catchallIncognito") private var catchallIncognito: Bool = false

    var body: some View {
        RuleForm(
            rule: Rule(regex: "", targets: catchallTargets, isIncognito: catchallIncognito),
            isCatchall: true,
            onCancel: {
                isPresented.toggle()
            },
            onSave: {
                catchallTargets = $0.targets
                catchallIncognito = $0.isIncognito
                isPresented.toggle()
            },
            onDelete: {
                isPresented.toggle()
            }
        )
    }
}

/// One "Open in:" row. A row exists before its browser is chosen, so it
/// can't be a BrowserTarget yet.
private struct TargetRow: Identifiable {
    let id = UUID()
    var app: URL?
    var profile: String?
}

struct RuleForm: View {
    var rule: Rule?
    /// Hides Regex, Test URLs, Port and Delete, and allows no browser at all.
    var isCatchall: Bool = false
    
    var onCancel: () -> Void
    var onSave: (Rule) -> Void
    var onDelete: () -> Void

    @State private var regex: String = ""
    @AppStorage("ruleTestUrls") private var testUrls: String = "https://github.com/AlexStrNik/Browserino\nhttps://x.com/alexstrnik"
    @State private var rows: [TargetRow] = []
    @State private var portText: String = ""
    @State private var isIncognito: Bool = false
    
    /// nil while the field is empty or not a valid port.
    private var parsedPort: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let value = Int(trimmed), (1...65535).contains(value) else {
            return nil
        }
        return value
    }
    
    private var portIsValid: Bool {
        portText.trimmingCharacters(in: .whitespaces).isEmpty || parsedPort != nil
    }
    
    private var compiledRegex: Regex<AnyRegexOutput>? {
        return try? Regex(regex).ignoresCase()
    }

    private var canSave: Bool {
        if rows.contains(where: { $0.app == nil }) {
            return false
        }

        if isCatchall {
            return true
        }

        return !rows.isEmpty && compiledRegex != nil && portIsValid
    }

    /// Row order is the picker order, and Return opens the first.
    private var targets: [BrowserTarget] {
        rows.compactMap { row in
            row.app.map { BrowserTarget(app: $0, profile: row.profile) }
        }
        .withoutDuplicates
    }
    
    private var attributtedText: AttributedString {
        var string = AttributedString(testUrls)
        guard let compiledRegex else {
            return string
        }
        
        for line in testUrls.split(separator: "\n") {
            if line.firstMatch(of: compiledRegex) != nil, let range = string.range(of: line) {
                string[range].foregroundColor = .red
            }
        }
        
        return string
    }
    
    var body: some View {
        Form {
            if isCatchall {
                Text("Default catchall")
                    .font(.headline)
            } else {
                Section(
                    header: Text("General")
                        .font(.headline)
                ) {
                    TextField("Regex:", text: $regex)
                        .font(
                            .system(size: 14)
                        )
                    
                    LabeledContent("Test URLs:") {
                        TextEditor(text: $testUrls)
                            .font(
                                .system(size: 14)
                            )
                    }
                    
                    Text(attributtedText)
                        .font(
                            .system(size: 14)
                        )
                }
            }
            
            Spacer()
                .frame(height: 32)
            
            
            LabeledContent("Open in:") {
                VStack(alignment: .leading) {
                    if rows.isEmpty {
                        Text("All browsers (picker)")
                            .foregroundStyle(.secondary)
                    }

                    ForEach($rows) { $row in
                        HStack {
                            BrowserTargetPicker(app: $row.app, profile: $row.profile)

                            // A rule needs a browser; Default catchall can go
                            // back to the full picker.
                            if isCatchall || rows.count > 1 {
                                Button {
                                    rows.removeAll { $0.id == row.id }
                                } label: {
                                    Image(systemName: "minus")
                                }
                                .help("Remove this browser")
                            }
                        }
                    }

                    Button("Add browser") {
                        rows.append(TargetRow())
                    }

                    Text(
                        isCatchall
                            ? "With no browser, links show the picker with all browsers."
                            : "With two or more browsers, matching links show the picker with only these."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            
            if !isCatchall {
                TextField("Port:", text: $portText, prompt: Text("Any"))
                    .font(
                        .system(size: 14)
                    )
                    .help("Leave empty to match any port. Links without a port count as 80 for http and 443 for https.")
            }
            
            Toggle("Private window", isOn: $isIncognito)
                .font(
                    .system(size: 14)
                )
                .help("Opens the link with the browser's private argument from the Browsers tab.")
            
            Spacer()
                .frame(height: 32)
            
            HStack {
                Button(role: .cancel, action: onCancel) {
                    Text("Cancel")
                }
                
                if rule != nil && !isCatchall {
                    Button(role: .destructive, action: onDelete) {
                        Text("Delete")
                    }
                }
                
                Spacer()
                
                Button(action: {
                    guard canSave else {
                        return
                    }
                    
                    onSave(
                        Rule(
                            regex: isCatchall ? "" : regex,
                            targets: targets,
                            port: isCatchall ? nil : parsedPort,
                            isIncognito: isIncognito
                        )
                    )
                }) {
                    Text("Save")
                }
                .disabled(!canSave)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(minWidth: 500)
        .onAppear {
            regex = rule?.regex ?? ""
            rows = (rule?.targets ?? []).map {
                TargetRow(app: $0.app, profile: $0.profile)
            }
            // A new rule starts with one browser to choose.
            if rows.isEmpty && !isCatchall {
                rows = [TargetRow()]
            }
            portText = rule?.port.map(String.init) ?? ""
            isIncognito = rule?.isIncognito ?? false
        }
    }
}
