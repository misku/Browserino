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
    private weak var anchor: NSView?
    private var pending: DispatchWorkItem?

    func show(_ text: String, for view: NSView) {
        pending?.cancel()
        anchor = view

        let work = DispatchWorkItem { [weak self, weak view] in
            MainActor.assumeIsolated {
                guard let self, let view, self.anchor === view else {
                    return
                }

                self.present(text, below: view)
            }
        }
        pending = work

        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100), execute: work)
    }

    func hide(for view: NSView) {
        guard anchor === view else {
            return
        }

        pending?.cancel()
        pending = nil
        anchor = nil
        panel?.orderOut(nil)
    }

    private func present(_ text: String, below view: NSView) {
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else {
            return
        }

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let content = NSHostingView(
            rootView: Text(text)
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

        let anchorRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let visible = screen.visibleFrame

        var origin = NSPoint(x: anchorRect.midX - size.width / 2, y: anchorRect.minY - size.height - 6)
        if origin.y < visible.minY {
            origin.y = anchorRect.maxY + 6
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

/// Watches the pointer for HoverBubble. A tracking area reports enter and exit
/// to its owner whatever the hit testing says, so the view stays out of the
/// way of clicks on the content it sits behind.
private struct HoverBubbleAnchor: NSViewRepresentable {
    let text: String

    final class AnchorView: NSView {
        var text = ""
        private var trackingArea: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()

            if let trackingArea {
                removeTrackingArea(trackingArea)
            }

            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                owner: self
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            HoverBubble.shared.show(text, for: self)
        }

        override func mouseExited(with event: NSEvent) {
            HoverBubble.shared.hide(for: self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if window == nil {
                HoverBubble.shared.hide(for: self)
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.text = text
        return view
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.text = text
    }
}

extension View {
    /// Shows `text` in a bubble about 0.1 s after the pointer enters the view.
    /// Use .help for everything else: its short system delay keeps tooltips
    /// from flashing while the pointer crosses a row of buttons.
    func hoverBubble(_ text: String) -> some View {
        background(HoverBubbleAnchor(text: text))
    }
}
