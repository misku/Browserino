//
//  View+Tooltip.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 12.10.2025.
//

import SwiftUI
import AppKit

/// A tooltip that appears almost at once, for places where the system help tag
/// would be too slow: the icon group of a rule names the browsers behind a
/// row of icons, and people sweep across it to find one. It lives in its own
/// borderless panel, so neither a scroll view nor the next row can clip it.
@MainActor
final class HoverBubble {
    static let shared = HoverBubble()

    private var panel: NSPanel?
    private var owner: UUID?
    private var pending: DispatchWorkItem?

    func show(_ content: AnyView, for token: UUID) {
        pending?.cancel()
        owner = token

        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.owner == token else {
                    return
                }

                self.present(content, near: NSEvent.mouseLocation)
            }
        }
        pending = work

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    func hide(for token: UUID) {
        guard owner == token else {
            return
        }

        pending?.cancel()
        pending = nil
        owner = nil
        panel?.orderOut(nil)
    }

    /// For when the view under the pointer goes away without reporting it:
    /// the window closes or another pane replaces it.
    func hideAll() {
        pending?.cancel()
        pending = nil
        owner = nil
        panel?.orderOut(nil)
    }

    /// Below the pointer, clear of the cursor image; above it when the screen
    /// ends first.
    private func present(_ bubble: AnyView, near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let content = NSHostingView(
            rootView: bubble
                .font(.callout)
                .monospacedDigit()
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15))
                }
        )
        let size = content.fittingSize
        content.frame = NSRect(origin: .zero, size: size)
        panel.contentView = content

        let visible = screen.visibleFrame
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 22)
        if origin.y < visible.minY {
            origin.y = point.y + 12
        }
        origin.x = min(max(origin.x, visible.minX + 4), visible.maxX - size.width - 4)

        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.transient, .ignoresCycle]

        return panel
    }
}

/// Pure SwiftUI hover tracking: nothing is layered over the content, so it
/// can't take a click meant for the view underneath.
private struct HoverBubbleModifier: ViewModifier {
    let content: AnyView

    @State private var token = UUID()

    func body(content: Content) -> some View {
        content
            .onHover { isInside in
                if isInside {
                    HoverBubble.shared.show(self.content, for: token)
                } else {
                    HoverBubble.shared.hide(for: token)
                }
            }
            .onDisappear {
                HoverBubble.shared.hide(for: token)
            }
    }
}

extension View {
    /// Shows `text` in a bubble about 0.1 s after the pointer enters the view.
    /// Use .help for everything else: its short system delay keeps tooltips
    /// from flashing while the pointer crosses a row of buttons.
    func hoverBubble(_ text: String) -> some View {
        hoverBubble { Text(text) }
    }

    /// The same bubble with any content, such as a table of browsers.
    func hoverBubble<Bubble: View>(@ViewBuilder _ bubble: () -> Bubble) -> some View {
        modifier(HoverBubbleModifier(content: AnyView(bubble())))
    }
}
