//
//  EditorSplitDividerHandle.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Hosts `EditorSplitDividerHandleView` over a divider's grab area: the system
/// resize cursor for its orientation, and the drag reported along its axis.
struct EditorSplitDividerHandle: NSViewRepresentable {
    let orientation: EditorSplitDivider.Orientation
    let onDragBegan: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    func makeNSView(context _: Context) -> EditorSplitDividerHandleView {
        let view = EditorSplitDividerHandleView()
        configure(view)
        return view
    }

    func updateNSView(_ view: EditorSplitDividerHandleView, context _: Context) {
        configure(view)
    }

    private func configure(_ view: EditorSplitDividerHandleView) {
        view.cursor = orientation == .vertical ? .resizeLeftRight : .resizeUpDown
        view.onDragBegan = onDragBegan
        view.onDragChanged = { onDragChanged(EditorSplitDivider.translation(of: $0, along: orientation)) }
        view.onDragEnded = { onDragEnded(EditorSplitDivider.translation(of: $0, along: orientation)) }
    }
}
