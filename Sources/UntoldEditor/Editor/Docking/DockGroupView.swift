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

/// One area of the layout: its tab strip and the front panel's content. The
/// whole area lights up while a dragged tab hovers it.
struct DockGroupView: View {
    let area: DockArea
    let size: CGSize
    @ObservedObject var layout: EditorDockLayout
    let registry: EditorPanelRegistry

    private var isDropTarget: Bool {
        layout.tabDragTarget == .area(area)
    }

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
    }
}
