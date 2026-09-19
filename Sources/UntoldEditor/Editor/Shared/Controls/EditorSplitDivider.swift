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

/// The hairline between two docked panels: one point of `editorHairline` inside
/// a 7 pt grab area. A drag reports the pointer's movement across the line, one
/// delta per event, so the owner can resize the panels on either side.
struct EditorSplitDivider: View {
    enum Orientation {
        /// A vertical line between panels placed side by side; drags move left and right.
        case vertical
        /// A horizontal line between panels stacked vertically; drags move up and down.
        case horizontal
    }

    let orientation: Orientation
    var onDragBegan: () -> Void = {}
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @State private var lastTranslation: CGFloat = 0
    @State private var isDragging = false

    var body: some View {
        Color.editorHairline
            .frame(width: lineWidth, height: lineHeight)
            .frame(width: grabWidth, height: grabHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if isDragging == false {
                            isDragging = true
                            onDragBegan()
                        }
                        let translation = Self.translation(of: value.translation, along: orientation)
                        onDrag(translation - lastTranslation)
                        lastTranslation = translation
                    }
                    .onEnded { _ in
                        lastTranslation = 0
                        isDragging = false
                        onDragEnded()
                    }
            )
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
