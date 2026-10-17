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

/// Sets the pointer over a region on macOS 14, which has no pointerStyle.
/// Cursor rects belong to the window, so the view can stay out of hit testing
/// and leave clicks and drags to the SwiftUI view it sits behind.
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    final class CursorAreaView: NSView {
        var cursor: NSCursor = .arrow {
            didSet {
                window?.invalidateCursorRects(for: self)
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: cursor)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }
    }

    func makeNSView(context: Context) -> CursorAreaView {
        let view = CursorAreaView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorAreaView, context: Context) {
        if nsView.cursor != cursor {
            nsView.cursor = cursor
        }
    }
}

extension View {
    /// An open hand over something that can be dragged, a closed one while it is.
    @ViewBuilder
    func grabCursor(isDragging: Bool) -> some View {
        if #available(macOS 15.0, *) {
            self.pointerStyle(isDragging ? PointerStyle.grabActive : PointerStyle.grabIdle)
        } else {
            self.background(CursorArea(cursor: isDragging ? .closedHand : .openHand))
        }
    }
}

/// The grip at the start of a reorderable row. It is the only place a drag
/// starts, so the buttons and fields in the rest of the row stay clickable.
struct ReorderHandle: View {
    let isDragging: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(isDragging ? .secondary : .tertiary)
            .frame(width: 16, height: 28)
            .contentShape(Rectangle())
            .grabCursor(isDragging: isDragging)
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { onChanged($0.translation.height) }
                    .onEnded { _ in onEnded() }
            )
            .help("Drag to reorder")
            .accessibilityHidden(true)
    }
}

/// A vertical stack whose rows are reordered by dragging their handle.
/// SwiftUI's List drags whole rows and owns the pointer while it does; this
/// keeps the drag on the handle and shows the closed hand throughout.
///
/// Rows slide aside to make room while dragging, and `move` is called once on
/// release with the row's old and new index.
struct ReorderableStack<Item, ID: Hashable, Row: View>: View {
    let items: [Item]
    let id: (Item) -> ID
    var spacing: CGFloat = 0
    var onDragStarted: () -> Void = {}
    let move: (_ from: Int, _ to: Int) -> Void
    @ViewBuilder let row: (_ item: Item, _ index: Int, _ handle: ReorderHandle) -> Row

    private struct Entry: Identifiable {
        let id: ID
        let index: Int
        let item: Item
    }

    @State private var frames: [ID: CGRect] = [:]
    @State private var dragged: ID?
    @State private var draggedIndex = 0
    @State private var target = 0
    @State private var translation: CGFloat = 0
    @State private var spaceName = UUID()

    private var entries: [Entry] {
        items.enumerated().map { Entry(id: id($0.element), index: $0.offset, item: $0.element) }
    }

    private func targetIndex(for translation: CGFloat) -> Int {
        guard let dragged, let frame = frames[dragged] else {
            return draggedIndex
        }

        let middle = frame.midY + translation
        var result = draggedIndex

        for entry in entries where entry.id != dragged {
            guard let other = frames[entry.id] else {
                continue
            }

            if entry.index > draggedIndex && middle > other.midY {
                result = max(result, entry.index)
            } else if entry.index < draggedIndex && middle < other.midY {
                result = min(result, entry.index)
            }
        }

        return result
    }

    private func offset(for entry: Entry) -> CGFloat {
        guard let dragged else {
            return 0
        }

        if entry.id == dragged {
            return translation
        }

        let room = (frames[dragged]?.height ?? 0) + spacing

        if draggedIndex < target, entry.index > draggedIndex, entry.index <= target {
            return -room
        }

        if target < draggedIndex, entry.index >= target, entry.index < draggedIndex {
            return room
        }

        return 0
    }

    private func handle(for entry: Entry) -> ReorderHandle {
        ReorderHandle(
            isDragging: dragged == entry.id,
            onChanged: { height in
                if dragged == nil {
                    dragged = entry.id
                    draggedIndex = entry.index
                    target = entry.index
                    onDragStarted()
                }

                translation = height

                let newTarget = targetIndex(for: height)
                if newTarget != target {
                    withAnimation(.snappy(duration: 0.2)) {
                        target = newTarget
                    }
                }
            },
            onEnded: {
                let from = draggedIndex
                let to = target

                withAnimation(.snappy(duration: 0.2)) {
                    dragged = nil
                    translation = 0

                    if from != to {
                        move(from, to)
                    }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(entries) { entry in
                row(entry.item, entry.index, handle(for: entry))
                    .background {
                        // Measured before the offset, so frames are the resting
                        // layout the drag is compared against.
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .named(spaceName))

                            Color.clear
                                .onAppear { frames[entry.id] = frame }
                                .onChange(of: frame) { _, newFrame in
                                    frames[entry.id] = newFrame
                                }
                        }
                    }
                    .background {
                        if dragged == entry.id {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.background)
                                .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                        }
                    }
                    .offset(y: offset(for: entry))
                    .zIndex(dragged == entry.id ? 1 : 0)
            }
        }
        .coordinateSpace(.named(spaceName))
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
