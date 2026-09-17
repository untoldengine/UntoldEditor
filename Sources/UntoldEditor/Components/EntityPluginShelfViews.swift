//
//  EntityPluginShelfViews.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// The rows that loaded code added to one creation shelf of the Content browser. They look
/// and behave like the built-in rows next to them: drag one into the viewport or onto the
/// hierarchy, or double-click it to create the entity at the origin.
///
/// The rows follow the component libraries: they appear when a library loads, change when it
/// reloads, and go when the project closes.
struct EntityPluginShelfRows: View {
    let shelf: UntoldEntityShelf
    let sceneGraphModel: SceneGraphModel
    let selectionManager: SelectionManager
    let showStatus: (String, Bool) -> Void

    @ObservedObject private var library = ComponentLibraryController.shared

    var body: some View {
        // Reading the revision ties the rows to a reload; the registry itself is not observable.
        let items = library.revision >= 0 ? EntityPluginShelfItem.items(on: shelf) : []
        ForEach(items) { item in
            row(item)
        }
        if items.isEmpty, shelf == .entities {
            Text("No entity kinds are loaded.")
                .font(.system(size: 12))
                .foregroundColor(.editorTextTertiary)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
        }
    }

    private func row(_ item: EntityPluginShelfItem) -> some View {
        HStack {
            Image(systemName: item.systemImage)
                .foregroundColor(.editorTextTertiary)
            Text(item.displayName)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.editorTextTertiary)
                .help("Added by the project's code or one of its plugins (\(item.typeName))")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(EntityPluginDragPayload(entityPlugin: item.typeName))
        .onTapGesture(count: 2) {
            if let placement = placeEntityPlugin(item.typeName, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager) {
                showStatus(placement.statusMessage, placement.isError)
            } else {
                showStatus("'\(item.displayName)' is no longer loaded.", true)
            }
        }
    }
}

/// Fixed left-tree entry for the Entities shelf, next to Primitives and Lights. It holds the
/// kinds of entity that fit neither, and takes no room until loaded code adds one.
struct EntityPluginsCategoryRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    @ObservedObject private var library = ComponentLibraryController.shared

    var body: some View {
        if library.revision >= 0, EntityPluginShelfItem.items(on: .entities).isEmpty == false || isSelected {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.clear)
                    .frame(width: 10)

                Image(systemName: isSelected ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
                Text(UntoldEntityShelf.entities.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.editorTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .padding(.leading, 12)
            .background(isSelected ? Color.editorAccentSoft : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
    }
}
