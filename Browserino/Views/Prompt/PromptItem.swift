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
    var action: () -> Void

    /// A stored value that is not a letter or digit is ignored rather than bound,
    /// so it can never take over Return, Escape or the arrow keys.
    private var keyEquivalent: KeyEquivalent? {
        PickerShortcut.keyEquivalent(for: shortcut)
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(
                        .system(size: 12, weight: .bold)
                    )
                
                Spacer()
                
                if let shortcut, keyEquivalent != nil {
                    Text(shortcut)
                        .font(.caption)
                        .frame(minWidth: 4)
                        .opacity(0.5)
                        .padding(5)
                        .background(
                            Color.secondary.opacity(0.2)
                        )
                        .cornerRadius(4)
                }
                
                Spacer()
                    .frame(width: 8)
                
                BrowserTargetIcon(target: target, badgeSize: 11)
                    .frame(width: 24, height: 24)
            }
            .padding(8)
        }
        .if(keyEquivalent != nil) {
            return $0.keyboardShortcut(
                keyEquivalent!,
                modifiers: [.shift]
            ).background {
                Button(action: action) {}
                    .opacity(0)
                    .keyboardShortcut(
                        keyEquivalent!,
                        modifiers: []
                    )
            }
        }
    }
}
