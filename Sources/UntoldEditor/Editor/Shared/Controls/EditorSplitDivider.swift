//
//  EditorSplitDivider.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The hairline between a docked area and the viewport: one point of
/// `editorHairline` inside a 7 pt grab area that shows the system resize
/// cursor. A drag reports the pointer's movement across the line since the
/// drag began, so the owner can show where the line will land and resize once
/// the mouse goes up.
struct EditorSplitDivider: View {
    enum Orientation {
        /// A vertical line between panels placed side by side; drags move left and right.
        case vertical
        /// A horizontal line between panels stacked vertically; drags move up and down.
        case horizontal
    }

    let orientation: Orientation
    var onDragBegan: () -> Void = {}
    /// The movement since the drag began, one value per mouse event.
    var onDragChanged: (CGFloat) -> Void = { _ in }
    /// The movement when the mouse goes up.
    var onDragEnded: (CGFloat) -> Void = { _ in }

    var body: some View {
        Color.editorHairline
            .frame(width: lineWidth, height: lineHeight)
            .frame(width: grabWidth, height: grabHeight)
            .overlay {
                EditorSplitDividerHandle(orientation: orientation, onDragBegan: onDragBegan, onDragChanged: onDragChanged, onDragEnded: onDragEnded)
            }
    }

    /// The component of a drag that moves the divider: horizontal movement for a
    /// vertical line, vertical movement for a horizontal one.
    static func translation(of size: CGSize, along orientation: Orientation) -> CGFloat {
        orientation == .vertical ? size.width : size.height
    }

    private var lineWidth: CGFloat? {
        orientation == .vertical ? 1 : nil
    }

    private var lineHeight: CGFloat? {
        orientation == .horizontal ? 1 : nil
    }

    private var grabWidth: CGFloat? {
        orientation == .vertical ? 7 : nil
    }

    private var grabHeight: CGFloat? {
        orientation == .horizontal ? 7 : nil
    }
}
