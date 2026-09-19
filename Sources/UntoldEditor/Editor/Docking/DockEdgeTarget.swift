//
//  DockEdgeTarget.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The thin strip that stands in for an area with no panels: drop a tab on it
/// to dock the panel there, or click it to show the panels the area last held.
struct DockEdgeTarget: View {
    let area: DockArea
    @ObservedObject var layout: EditorDockLayout

    @State private var isDropTarget = false

    var body: some View {
        Rectangle()
            .fill(isDropTarget ? Color.editorAccentSoft : Color.editorControlFill)
            .overlay {
                Image(systemName: glyph)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isDropTarget ? .editorAccent : .editorTextTertiary)
            }
            .overlay {
                if isDropTarget {
                    Rectangle()
                        .stroke(Color.editorAccent, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                layout.toggleArea(area)
            }
            .help("Drop a panel here to dock it in the \(area.title.lowercased()), or click to show the area")
            .onDrop(
                of: [DockDropDelegate.dragType],
                delegate: DockDropDelegate(
                    target: .area(area),
                    size: .zero,
                    layout: layout,
                    highlightedArea: Binding(
                        get: { isDropTarget ? area : nil },
                        set: { isDropTarget = $0 != nil }
                    )
                )
            )
    }

    /// Points into the window, where the area would open.
    private var glyph: String {
        switch area {
        case .left: return "chevron.right"
        case .right: return "chevron.left"
        case .bottom: return "chevron.up"
        }
    }
}
