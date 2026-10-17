//
//  PromptItem.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 10.06.2024.
//

import SwiftUI

struct PromptItem: View {
    var target: BrowserTarget
    var title: String
    var shortcut: String?
    /// Called with whether Shift asked for the other window kind. Each way in
    /// says so itself: the live modifier state can miss a Shift that was part
    /// of the key press.
    var action: (_ withShift: Bool) -> Void

    /// A stored value that is not a letter or digit is ignored rather than bound,
    /// so it can never take over Return, Escape or the arrow keys.
    private var keyEquivalent: KeyEquivalent? {
        PickerShortcut.keyEquivalent(for: shortcut)
    }

    var body: some View {
        Button {
            action(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let shortcut, keyEquivalent != nil {
                    // Drawn like a key on the keyboard, which is what it is.
                    Text(shortcut)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(minWidth: 18, minHeight: 18)
                        .background {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15))
                        }
                        .opacity(0.8)
                }

                BrowserTargetIcon(target: target, badgeSize: 10)
                    .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .if(keyEquivalent != nil) {
            $0.background {
                Button {
                    action(false)
                } label: {}
                .opacity(0)
                .keyboardShortcut(keyEquivalent!, modifiers: [])

                Button {
                    action(true)
                } label: {}
                .opacity(0)
                .keyboardShortcut(keyEquivalent!, modifiers: [.shift])
            }
        }
    }
}
