//
//  DockGroupView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One area of the layout: its tab strip and the front panel's content, and the
/// drop target that lets a dragged tab join the area. The whole area lights up
/// while a tab hovers it.
struct DockGroupView: View {
    let area: DockArea
    let size: CGSize
    @ObservedObject var layout: EditorDockLayout
    let registry: EditorPanelRegistry

    @State private var isDropTarget = false

    var body: some View {
        let state = layout.state[area]
        VStack(spacing: 0) {
            DockTabStrip(
                state: state,
                layout: layout,
                accessories: state.selected.flatMap(registry.accessories),
                accessoryPlacement: area.accessoryPlacement
            )
            if let selected = state.selected {
                registry.content(selected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .background(Color.editorPanelBackground)
        .overlay {
            DockDropZoneHighlight(rect: isDropTarget ? CGRect(origin: .zero, size: size).insetBy(dx: 3, dy: 3) : nil)
        }
        .onDrop(
            of: [DockDropDelegate.dragType],
            delegate: DockDropDelegate(
                target: .area(area),
                size: size,
                layout: layout,
                highlightedArea: Binding(
                    get: { isDropTarget ? area : nil },
                    set: { isDropTarget = $0 != nil }
                )
            )
        )
    }
}
