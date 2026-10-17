//
//  ButtonStyles.swift
//  Browserino
//
//  Created by Aleksandr Strizhnev on 06.06.2024.
//

import AppKit
import SwiftUI
import Foundation

struct BackgroundOnHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background(isHovered ? Color.secondary.opacity(0.5) : .clear)
            .onHover { isHovered in
                withAnimation {
                    self.isHovered = isHovered
                }
            }
    }
}

struct SelectButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .contentShape(RoundedRectangle(cornerSize: CGSize(width: 8, height: 8)))
            .foregroundStyle(self.selected ? Color.white : Color.primary)
            .background(configuration.isPressed || selected ? Color.accentColor : .clear)
            .modifier(BackgroundOnHover())
            .cornerRadius(8)
    }
}

/// The one look for icon-only buttons across Settings: a 24pt square with a
/// faint fill, so it reads as a button without the weight of a bordered
/// control in every row. Flat on purpose: macOS 26 keeps glass for toolbars,
/// not for rows of content.
///
/// `isOn` makes it a toggle. nil is a plain action, false an off toggle drawn
/// in grey, true an on toggle drawn filled in the accent colour.
struct IconButtonStyle: ButtonStyle {
    var isOn: Bool? = nil

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, isOn: isOn)
    }
}

/// A ButtonStyle cannot hold state, and hover needs some.
private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isOn: Bool?

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    private var fillOpacity: Double {
        if isOn == true {
            return configuration.isPressed ? 0.3 : 0.18
        }

        if configuration.isPressed {
            return 0.16
        }

        return isHovered && isEnabled ? 0.1 : 0.05
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        configuration.label
            .font(.system(size: 13, weight: .medium))
            .symbolVariant(isOn == true ? .fill : .none)
            .foregroundStyle(
                isOn == true ? AnyShapeStyle(Color.accentColor)
                    : isOn == false ? AnyShapeStyle(.secondary)
                    : AnyShapeStyle(.primary)
            )
            .frame(width: 24, height: 24)
            .background {
                shape.fill(isOn == true ? Color.accentColor.opacity(fillOpacity) : Color.primary.opacity(fillOpacity))
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { isHovered = $0 }
    }
}

/// An icon button with the tooltip and VoiceOver label every icon-only
/// control needs, so neither can be forgotten.
struct IconButton: View {
    let systemImage: String
    let help: String
    var label: String? = nil
    var isOn: Bool? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(IconButtonStyle(isOn: isOn))
        .help(help)
        .accessibilityLabel(label ?? help)
        .accessibilityValue(isOn.map { $0 ? "On" : "Off" } ?? "")
    }
}

/// An entry in the menu a reorder handle shows on a right-click.
enum HandleMenuItem {
    case action(_ title: String, isEnabled: Bool = true, _ handler: () -> Void)
    case separator
}

/// Runs a menu item's closure. NSMenuItem holds its target weakly, so the
/// handle keeps these alive for as long as its menu exists.
@MainActor
private final class HandleMenuTarget: NSObject {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

/// The grip at the start of a reorderable row, built on an AppKit view. A
/// SwiftUI gesture here competed with the row's buttons, menus and the
/// scroll view, and never got the pointer to stay a closed hand. This view
/// takes the mouse itself: an open hand on hover, a closed hand from press to
/// release, and the list scrolls when the pointer leaves it while dragging.
struct ReorderHandle: View {
    let isDragging: Bool
    /// How far the row has been dragged, positive downwards. The first call
    /// starts the drag.
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    var menu: [HandleMenuItem] = []

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isDragging ? .secondary : .tertiary)
            .frame(width: 16, height: 28)
            .overlay {
                HandleArea(onChanged: onChanged, onEnded: onEnded, menu: menu)
            }
            .accessibilityHidden(true)
    }

    /// The same handle with row-specific commands ahead of the move commands.
    func addingMenu(_ items: [HandleMenuItem]) -> ReorderHandle {
        var handle = self
        handle.menu = items + [.separator] + menu
        return handle
    }
}

private struct HandleArea: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void
    let menu: [HandleMenuItem]

    final class HandleView: NSView {
        var onChanged: (CGFloat) -> Void = { _ in }
        var onEnded: () -> Void = {}
        var items: [HandleMenuItem] = []

        private var start: NSPoint?
        private var startScroll: CGFloat = 0
        private var isDragging = false
        private var menuTargets: [HandleMenuTarget] = []

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            toolTip = "Drag to reorder"
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }

        /// The scroll view's offset, so a drag that scrolls the list keeps the
        /// row under the pointer.
        private var scrollOffset: CGFloat {
            enclosingScrollView?.contentView.bounds.origin.y ?? 0
        }

        override func mouseDown(with event: NSEvent) {
            start = event.locationInWindow
            startScroll = scrollOffset
            isDragging = false

            // Other views' cursor rects would swap the hand for an arrow or an
            // I-beam as the pointer crosses them mid-drag.
            window?.disableCursorRects()
            NSCursor.closedHand.push()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start else {
                return
            }

            autoscroll(with: event)

            let flipped = enclosingScrollView?.contentView.isFlipped ?? true
            let scrolled = (scrollOffset - startScroll) * (flipped ? 1 : -1)
            let distance = start.y - event.locationInWindow.y + scrolled

            if !isDragging && abs(distance) < 3 {
                return
            }

            isDragging = true
            onChanged(distance)
        }

        override func mouseUp(with event: NSEvent) {
            guard start != nil else {
                return
            }

            start = nil
            NSCursor.pop()
            window?.enableCursorRects()
            window?.invalidateCursorRects(for: self)

            if isDragging {
                isDragging = false
                onEnded()
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard !items.isEmpty else {
                return nil
            }

            let menu = NSMenu()
            menu.autoenablesItems = false
            menuTargets = []

            for item in items {
                switch item {
                case .separator:
                    menu.addItem(.separator())
                case let .action(title, isEnabled, handler):
                    let target = HandleMenuTarget(handler)
                    menuTargets.append(target)

                    let menuItem = NSMenuItem(title: title, action: #selector(HandleMenuTarget.run), keyEquivalent: "")
                    menuItem.target = target
                    menuItem.isEnabled = isEnabled
                    menu.addItem(menuItem)
                }
            }

            return menu
        }
    }

    func makeNSView(context: Context) -> HandleView {
        HandleView()
    }

    func updateNSView(_ nsView: HandleView, context: Context) {
        nsView.onChanged = onChanged
        nsView.onEnded = onEnded
        nsView.items = menu
    }
}

/// Drag state for ReorderableStack. A class, so the gesture callbacks always
/// read what they just wrote, and row heights can be recorded without
/// redrawing the list each time.
@MainActor
private final class ReorderModel<ID: Hashable>: ObservableObject {
    @Published var dragged: ID?
    @Published var target = 0
    @Published var translation: CGFloat = 0
    var draggedIndex = 0
    var heights: [ID: CGFloat] = [:]
}

/// A vertical stack whose rows are reordered by dragging their handle.
/// Rows slide aside to make room while dragging, and `move` is called once on
/// release with the row's old and new index.
struct ReorderableStack<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: (Item) -> ID
    var spacing: CGFloat = 0
    var onDragStarted: () -> Void = {}
    let move: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (_ item: Item, _ index: Int, _ handle: ReorderHandle) -> Row

    @StateObject private var model = ReorderModel<ID>()

    private struct Entry: Identifiable {
        let id: ID
        let index: Int
        let item: Item
    }

    private var entries: [Entry] {
        items.enumerated().map { Entry(id: id($0.element), index: $0.offset, item: $0.element) }
    }

    private func height(of id: ID) -> CGFloat {
        model.heights[id] ?? 44
    }

    /// The slot the dragged row would land in: it passes a neighbour once its
    /// middle crosses the neighbour's middle.
    private func targetIndex(for translation: CGFloat, in ids: [ID]) -> Int {
        let from = model.draggedIndex
        var result = from

        if translation > 0 {
            var travelled: CGFloat = 0
            for index in ids.indices where index > from {
                let next = height(of: ids[index]) + spacing
                if translation > travelled + next / 2 {
                    result = index
                    travelled += next
                } else {
                    break
                }
            }
        } else if translation < 0 {
            var travelled: CGFloat = 0
            for index in ids.indices.reversed() where index < from {
                let previous = height(of: ids[index]) + spacing
                if -translation > travelled + previous / 2 {
                    result = index
                    travelled += previous
                } else {
                    break
                }
            }
        }

        return result
    }

    private func offset(for entry: Entry) -> CGFloat {
        guard let dragged = model.dragged else {
            return 0
        }

        if entry.id == dragged {
            return model.translation
        }

        let room = height(of: dragged) + spacing
        let from = model.draggedIndex
        let target = model.target

        if from < target, entry.index > from, entry.index <= target {
            return -room
        }

        if target < from, entry.index >= target, entry.index < from {
            return room
        }

        return 0
    }

    private func handle(for entry: Entry, ids: [ID]) -> ReorderHandle {
        ReorderHandle(
            isDragging: model.dragged == entry.id,
            onChanged: { distance in
                if model.dragged == nil {
                    model.draggedIndex = entry.index
                    model.target = entry.index
                    model.dragged = entry.id
                    onDragStarted()
                }

                model.translation = distance

                let newTarget = targetIndex(for: distance, in: ids)
                if newTarget != model.target {
                    withAnimation(.snappy(duration: 0.2)) {
                        model.target = newTarget
                    }
                }
            },
            onEnded: {
                let from = model.draggedIndex
                let to = model.target

                withAnimation(.snappy(duration: 0.2)) {
                    model.dragged = nil
                    model.translation = 0

                    if from != to {
                        move(from, to)
                    }
                }
            },
            menu: [
                .action("Move Up", isEnabled: entry.index > 0) {
                    move(entry.index, entry.index - 1)
                },
                .action("Move Down", isEnabled: entry.index < ids.count - 1) {
                    move(entry.index, entry.index + 1)
                },
                .action("Move to Top", isEnabled: entry.index > 0) {
                    move(entry.index, 0)
                },
                .action("Move to Bottom", isEnabled: entry.index < ids.count - 1) {
                    move(entry.index, ids.count - 1)
                },
            ]
        )
    }

    var body: some View {
        let allEntries = self.entries
        let ids = allEntries.map(\.id)

        VStack(spacing: spacing) {
            ForEach(allEntries) { entry in
                row(entry.item, entry.index, handle(for: entry, ids: ids))
                    .background {
                        // Heights only: where a row sits follows from the rows
                        // above it, and recording this redraws nothing.
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { model.heights[entry.id] = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, newHeight in
                                    model.heights[entry.id] = newHeight
                                }
                        }
                        .allowsHitTesting(false)
                    }
                    .background {
                        if model.dragged == entry.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(y: offset(for: entry))
                    .zIndex(model.dragged == entry.id ? 1 : 0)
            }
        }
    }
}

extension Array {
    /// Moves the element at `from` so that it ends up at index `to`, the
    /// convention ReorderableStack reports.
    mutating func move(from: Int, to: Int) {
        guard from != to, indices.contains(from), indices.contains(to) else {
            return
        }

        insert(remove(at: from), at: to)
    }
}

/// The grouped look of System Settings for a list of rows: one rounded
/// container, hairlines between rows.
struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
                .allowsHitTesting(false)
        }
    }
}

/// The hairline between rows in a SettingsCard, inset like System Settings.
struct RowDivider: View {
    var leadingInset: CGFloat = 12

    var body: some View {
        Divider()
            .padding(.leading, leadingInset)
    }
}

/// The bar under a list: actions on the leading side, a hint on the trailing.
struct ListBottomBar<Actions: View>: View {
    let hint: String
    @ViewBuilder let actions: Actions

    var body: some View {
        HStack(spacing: 4) {
            actions

            Spacer(minLength: 12)

            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.top, 10)
    }
}
