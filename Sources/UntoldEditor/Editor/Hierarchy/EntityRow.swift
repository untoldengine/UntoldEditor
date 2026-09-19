//
//  EntityRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldEngine

// MARK: - Entity Row

struct EntityRow: View {
    let entityid: EntityID
    let entityName: String
    var hasChildren: Bool = false
    var isExpanded: Bool = true
    var onToggleExpanded: () -> Void = {}
    @ObservedObject var selectionManager: SelectionManager
    @State private var isDragOver = false

    private var isSelected: Bool {
        entityid == selectionManager.selectedEntity
    }

    private var isAssetNode: Bool {
        isDerivedAssetNode(entityid)
    }

    var body: some View {
        if isAssetNode {
            styledEntityRow
        } else {
            styledEntityRow
                .draggable(String(entityid))
        }
    }

    private var styledEntityRow: some View {
        entityRowContent
            .padding(8)
            .background(isSelected ? Color.editorSurface : Color.clear)
            .cornerRadius(6)
    }

    private var entityRowContent: some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpanded) {
                Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(hasChildren ? .editorTextSecondary : .clear)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(hasChildren == false)
            .help(isExpanded ? "Collapse Children" : "Expand Children")

            Image(systemName: hierarchyIconName(for: entityid))
                .foregroundColor(isSelected ? .editorTextPrimary : (isAssetNode ? .editorTextSecondary : .editorTextTertiary))

            Text(entityName)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .editorTextPrimary : (isAssetNode ? .editorTextSecondary : .editorTextPrimary))

            Spacer()
        }
    }
}
