//
//  ShortcutButton.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import AppKit
import SwiftUI

/// The picker binds a shortcut as a bare key and as Shift plus the key, next to
/// its own Return (open), Escape (close) and arrow keys (move). Only a letter or
/// a digit can never collide with those, and only those survive a keyboard
/// layout change as the same visible character.
enum PickerShortcut {
    static func isValid(_ key: String) -> Bool {
        guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else {
            return false
        }

        return (65...90).contains(scalar.value) || (48...57).contains(scalar.value)
    }

    /// The key the picker binds, or nil for anything an earlier build stored
    /// that is not a letter or digit.
    static func keyEquivalent(for shortcut: String?) -> KeyEquivalent? {
        guard let shortcut, isValid(shortcut), let character = shortcut.lowercased().first else {
            return nil
        }

        return KeyEquivalent(character)
    }
}

struct ShortcutButton: View {
    let shortcutKey: String

    @AppStorage("shortcuts") private var shortcuts: [String: String] = [:]

    @State private var isRecording: Bool = false
    @State private var isHovered: Bool = false
    @FocusState private var focus: Bool

    private var recordedKey: String? {
        shortcuts[shortcutKey].flatMap { PickerShortcut.isValid($0) ? $0 : nil }
    }

    private func record(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            isRecording = false
            return .handled
        }

        if press.key == .delete || press.key == .deleteForward {
            shortcuts[shortcutKey] = nil
            isRecording = false
            return .handled
        }

        let key = String(press.key.character).uppercased()

        guard press.modifiers.isDisjoint(with: [.command, .option, .control]),
              PickerShortcut.isValid(key)
        else {
            NSSound.beep()
            return .handled
        }

        // One key opens one browser, so taking a key moves it here.
        var updated = shortcuts.filter { $0.value != key }
        updated[shortcutKey] = key
        shortcuts = updated
        isRecording = false

        return .handled
    }

    var body: some View {
        if isRecording {
            Text("Type a key")
                .font(.callout)
                .foregroundStyle(Color.accentColor)
                .frame(width: 64, height: 22)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
                .contentShape(.rect)
                .focusable()
                .focusEffectDisabled()
                .focused($focus)
                .onAppear {
                    focus = true
                }
                .onChange(of: focus) { _, newFocus in
                    isRecording = newFocus
                }
                .onKeyPress(phases: .down) { press in
                    record(press)
                }
                .help("Type a letter or digit. Escape cancels, Delete removes the shortcut.")
                .accessibilityLabel("Recording shortcut")
        } else {
            Button(action: {
                isRecording = true
                focus = true
            }, label: {
                Text(recordedKey ?? "Record")
                    .font(recordedKey == nil ? Font.callout : Font.body.monospaced().weight(.medium))
                    .foregroundStyle(recordedKey == nil ? .secondary : .primary)
                    .frame(width: 64, height: 22)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(recordedKey == nil ? 0 : 0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.35))
                    }
                    .contentShape(.rect)
            })
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                if recordedKey != nil && isHovered {
                    Button {
                        shortcuts[shortcutKey] = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .help("Remove this shortcut")
                    .accessibilityLabel("Remove shortcut")
                }
            }
            .onHover { isHovered = $0 }
            .help(
                recordedKey.map { "Press \($0) in the picker to open this browser. Click to change it." }
                    ?? "Record a key that opens this browser from the picker"
            )
            .accessibilityLabel(recordedKey.map { "Shortcut \($0)" } ?? "Record shortcut")
        }
    }
}
