//
//  EditorSplitDividerHandleView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit

/// The AppKit side of a split divider: a cursor rect that shows the resize
/// cursor over the grab area, and a drag tracked in window coordinates, so the
/// movement it reports does not depend on where the divider is laid out. The
/// movement is a size with y growing downwards, as SwiftUI measures drags.
final class EditorSplitDividerHandleView: NSView {
    var cursor: NSCursor = .resizeLeftRight {
        didSet {
            if cursor !== oldValue {
                window?.invalidateCursorRects(for: self)
            }
        }
    }

    var onDragBegan: () -> Void = {}
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: (CGSize) -> Void = { _ in }

    /// Where the mouse went down, in window coordinates, until it goes up.
    private var dragOrigin: CGPoint?
    private var isDragging = false

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        dragOrigin = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        if isDragging == false {
            isDragging = true
            onDragBegan()
        }
        // Cursor rects only apply while no button is down; keep the resize
        // cursor while the pointer runs ahead of the line.
        cursor.set()
        onDragChanged(Self.translation(from: dragOrigin, to: event.locationInWindow))
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragOrigin else { return }
        self.dragOrigin = nil
        if isDragging {
            isDragging = false
            onDragEnded(Self.translation(from: dragOrigin, to: event.locationInWindow))
        }
    }

    /// The movement from `origin` to `location`, both in window coordinates
    /// (y up), as a drag translation (y down).
    nonisolated static func translation(from origin: CGPoint, to location: CGPoint) -> CGSize {
        CGSize(width: location.x - origin.x, height: origin.y - location.y)
    }
}
