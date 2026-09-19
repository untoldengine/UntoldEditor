//
//  SceneRootRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The root of the hierarchy tree: the loaded scene. Clicking it selects the
/// scene, whose properties show in the Inspector; the caret folds the whole
/// tree; an asset dropped on it lands at the scene root.
struct SceneRootRow: View {
    let name: String
    @Binding var isExpanded: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onDropRow: (DroppedRowPayload) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: { isExpanded.toggle() }) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.editorTextSecondary)
                    .frame(width: 8, height: 12)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isExpanded ? "Collapse the tree" : "Expand the tree")

            RoundedRectangle(cornerRadius: 2)
                .fill(Color.editorAccent)
                .frame(width: 12, height: 10)

            Text(name)
                .font(EditorType.title)
                .foregroundColor(isSelected ? .editorTextSelected : .editorTextPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .background(background)
        .cornerRadius(EditorType.Radius.field)
        .contentShape(Rectangle())
        .onDrop(of: [AssetDragPayload.contentType], isTargeted: $isDropTargeted) { providers in
            loadDroppedRowPayload(from: providers) { payload in
                onDropRow(payload)
            }
        }
        .onTapGesture(perform: onSelect)
        .help("Select the scene")
    }

    private var background: Color {
        if isDropTargeted {
            return Color.editorInfo.opacity(0.2)
        }
        return isSelected ? Color.editorAccentSoft : Color.clear
    }
}
