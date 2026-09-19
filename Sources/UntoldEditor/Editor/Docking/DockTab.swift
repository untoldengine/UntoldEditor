//
//  DockTab.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One tab of an area's strip. A click brings the panel to front, a drag by the
/// pointer carries it to another area (no system drag, so the pointer keeps
/// its shape), the context menu moves it to an area or closes it, and a close
/// button appears on hover.
struct DockTab: View {
    let panel: PanelID
    let isSelected: Bool
    /// The only tab of its area: drawn as a plain title rather than a pill.
    let isAlone: Bool
    @ObservedObject var layout: EditorDockLayout

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(panel.title)
                .font(isSelected ? EditorType.title : EditorType.body)
                .foregroundColor(isSelected ? Color.editorTextPrimary : Color.editorTextSecondary)
                .lineLimit(1)
            if panel.canClose, isHovering {
                Button {
                    layout.close(panel)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Close \(panel.title)")
            }
        }
        .padding(.horizontal, isAlone ? 2 : 10)
        .frame(height: 26)
        .background(isSelected && isAlone == false ? Color.editorControlActive : Color.clear)
        .cornerRadius(EditorType.Radius.field)
        .contentShape(Rectangle())
        .onTapGesture {
            layout.select(panel)
        }
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(DockContainerView.coordinateSpace))
                .onChanged { drag in
                    layout.tabDragMoved(panel, to: drag.location)
                    NSCursor.closedHand.set()
                }
                .onEnded { _ in
                    layout.tabDragEnded()
                    NSCursor.arrow.set()
                }
        )
        .contextMenu {
            ForEach(DockArea.allCases.filter { $0 != layout.area(of: panel) }) { area in
                Button("Move to \(area.title)") {
                    layout.move(panel, to: area)
                }
            }
            if panel.canClose {
                Divider()
                Button("Close") {
                    layout.close(panel)
                }
            }
        }
        .help("Drag to another area, or right-click for more")
    }
}
