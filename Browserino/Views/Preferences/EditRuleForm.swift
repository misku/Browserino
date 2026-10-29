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
    let onSave: (_ regex: String, _ port: Int?, _ portEnd: Int?) -> Void
    var onDelete: (() -> Void)? = nil

    @State private var regex: String = ""
    @AppStorage("ruleTestUrls") private var testUrls: String = "https://github.com/AlexStrNik/Browserino\nhttps://x.com/alexstrnik"
    @State private var portText: String = ""
    @State private var isRange = false
    /// Kept while the range is off, so turning it back on restores it.
    @State private var portEndText: String = ""
    @State private var confirmDelete = false
    @State private var isLoaded = false

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }

    /// nil while the field is empty or not a valid port.
    private static func parse(_ text: String) -> Int? {
        guard let value = Int(trimmed(text)), (1...65535).contains(value) else {
            return nil
        }
        return value
    }

    private var parsedPort: Int? {
        RuleForm.parse(portText)
    }

    /// The last port as saved: nil without a range, or when both ends are
    /// the same port.
    private var parsedPortEnd: Int? {
        guard isRange, let port = parsedPort, let end = RuleForm.parse(portEndText), end > port else {
            return nil
        }
        return end
    }

    /// Why the port line can't be saved, or nil when it can.
    private var portError: String? {
        let start = RuleForm.trimmed(portText)
        let end = RuleForm.trimmed(portEndText)

        if (!start.isEmpty && parsedPort == nil) || (isRange && !end.isEmpty && RuleForm.parse(end) == nil) {
            return "A port is a number from 1 to 65535."
        }

        guard isRange else {
            return nil
        }

        guard let port = parsedPort, let last = RuleForm.parse(end) else {
            return "Enter both ports for a range."
        }

        return port > last ? "The first port must not be larger than the last." : nil
    }

    private var portIsValid: Bool {
        portError == nil
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
        let rule = Rule(regex: pattern, targets: [], port: parsedPort, portEnd: parsedPortEnd)

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
                    TextField("Regex Pattern", text: $regex, prompt: Text("github\\.com/myorg"))
                        .font(.body.monospaced())

                    if !patternIsEmpty && Rule.compile(pattern) == nil {
                        Label("Not a valid regular expression.", systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }

                    LabeledContent(isRange ? "Port range" : "Port") {
                        HStack(spacing: 8) {
                            if isRange {
                                Text("from")
                                    .accessibilityHidden(true)
                            }

                            TextField("First port", text: $portText, prompt: Text(isRange ? "From" : "Any"))
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)

                            Toggle("Port range", isOn: $isRange)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            Text("to")
                                .foregroundStyle(isRange ? .primary : .tertiary)
                                .accessibilityHidden(true)

                            TextField("Last port", text: $portEndText, prompt: Text("To"))
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                                .disabled(!isRange)
                        }
                    }
                    .onChange(of: isRange) { _, isOn in
                        if isOn && RuleForm.trimmed(portEndText).isEmpty {
                            portEndText = portText
                        }
                    }

                    if let portError {
                        Label(portError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(original == nil ? "New Rule" : "Edit Rule")
                        .font(.headline)
                } footer: {
                    Text("A regular expression matched anywhere in the full link, ignoring case. Leave the port empty for any port; links without one count as 80 for http and 443 for https. Tick \"to\" to match every port from the first to the last, both included.")
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

                    onSave(pattern, parsedPort, parsedPortEnd)
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
            // Once: appear can fire again while the sheet is presented, and
            // must not throw away what the user typed.
            guard !isLoaded else {
                return
            }

            isLoaded = true
            regex = original?.regex ?? ""
            portText = original?.port.map(String.init) ?? ""

            if let end = original?.portEnd {
                portEndText = String(end)
                isRange = true
            }
        }
    }
}
