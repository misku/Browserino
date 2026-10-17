//
//  EditRuleForm.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 02.12.2024.
//

import SwiftUI

/// Adds or edits a rule's pattern and port. Its browsers and private setting
/// live in the rule's row, where they can be changed without opening a sheet.
struct RuleForm: View {
    let original: Rule?
    let onCancel: () -> Void
    let onSave: (_ regex: String, _ port: Int?) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var regex: String = ""
    @AppStorage("ruleTestUrls") private var testUrls: String = "https://github.com/AlexStrNik/Browserino\nhttps://x.com/alexstrnik"
    @State private var portText: String = ""
    @State private var confirmDelete = false

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

    /// A space before or after a pattern is invisible in the field and would
    /// make the rule miss every link, so it never reaches the rule.
    private var pattern: String {
        regex.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var patternIsEmpty: Bool {
        pattern.isEmpty
    }

    private var canSave: Bool {
        !patternIsEmpty && Rule.compile(pattern) != nil && portIsValid
    }

    /// Each test link and whether this rule, port included, would take it.
    private var testResults: [(link: String, matches: Bool)] {
        let rule = Rule(regex: pattern, targets: [], port: parsedPort)

        return testUrls
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { link -> (link: String, matches: Bool) in
                guard canSave, let url = URL(string: link) else {
                    return (link, false)
                }

                return (link, rule.matches(url))
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Pattern", text: $regex, prompt: Text("github\\.com/myorg"))
                        .font(.body.monospaced())

                    if !patternIsEmpty && Rule.compile(pattern) == nil {
                        Label("Not a valid regular expression.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    LabeledContent("Port") {
                        TextField("Port", text: $portText, prompt: Text("Any"))
                            .labelsHidden()
                            .font(.body.monospaced())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    if !portIsValid {
                        Label("A port is a number from 1 to 65535.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(original == nil ? "New Rule" : "Edit Rule")
                        .font(.headline)
                } footer: {
                    Text("A regular expression matched anywhere in the full link, ignoring case. Leave the port empty for any port; links without one count as 80 for http and 443 for https.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $testUrls)
                        .font(.callout.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(height: 64)

                    ForEach(Array(testResults.enumerated()), id: \.offset) { _, result in
                        HStack(spacing: 6) {
                            Image(systemName: result.matches ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(result.matches ? Color.green : Color.secondary)

                            Text(result.link)
                                .font(.callout.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(result.matches ? .primary : .secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(result.matches ? "Matches" : "No match")
                    }
                } header: {
                    Text("Test Links")
                } footer: {
                    Text("One link per line. A check means this rule would take the link.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if onDelete != nil {
                    Button("Delete Rule…", role: .destructive) {
                        confirmDelete = true
                    }
                }

                Spacer()

                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)

                Button(original == nil ? "Add Rule" : "Save") {
                    guard canSave else {
                        return
                    }

                    onSave(pattern, parsedPort)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(20)
        }
        .frame(width: 520, height: 540)
        .confirmationDialog("Delete this rule?", isPresented: $confirmDelete) {
            Button("Delete Rule", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Links it matches go to the next matching rule, or to All Other Links.")
        }
        .onAppear {
            regex = original?.regex ?? ""
            portText = original?.port.map(String.init) ?? ""
        }
    }
}
