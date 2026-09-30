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

/// One entity in the hierarchy: caret, type icon, name, then the eye and the
/// lock. A hidden entity, or one under a hidden parent, is greyed; the selected
/// row is on the accent.
struct EntityRow: View {
    let entityid: EntityID
    let entityName: String
    var hasChildren: Bool = false
    var isExpanded: Bool = true
    var onToggleExpanded: () -> Void = {}
    @ObservedObject var selectionManager: SelectionManager

    private var isSelected: Bool {
        entityid == selectionManager.selectedEntity
    }

    private var isAssetNode: Bool {
        isDerivedAssetNode(entityid)
    }

    /// The eye is off for this row.
    private var isHidden: Bool {
        selectionManager.isHidden(entityid)
    }

    /// Greyed: this row or a parent is hidden.
    private var isDimmed: Bool {
        selectionManager.isEffectivelyHidden(entityid)
    }

    private var isLocked: Bool {
        selectionManager.isLocked(entityid)
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
            .padding(.horizontal, 6)
            .frame(height: 28)
            .background(isSelected ? Color.editorAccentSoft : Color.clear)
            .cornerRadius(EditorType.Radius.field)
    }

    private var entityRowContent: some View {
        HStack(spacing: 6) {
            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(hasChildren ? .editorTextSecondary : .clear)
                    .frame(width: 8, height: 12)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(hasChildren == false)
            .help(isExpanded ? "Collapse Children" : "Expand Children")

            Image(systemName: hierarchyIconName(for: entityid))
                .font(.system(size: 11))
                .frame(width: 14)
                .foregroundColor(iconColor)

            Text(entityName)
                .font(isSelected ? EditorType.title : EditorType.body)
                .foregroundColor(textColor)
                .lineLimit(1)

            Spacer(minLength: 4)

            EntityRowToggle(
                systemImage: isHidden ? "eye.slash" : "eye",
                tint: isHidden ? .editorTextDisabled : .editorTextTertiary,
                help: isHidden ? "Show in the viewport" : "Hide in the viewport (H)"
            ) {
                selectionManager.toggleHidden(entityid)
            }
            EntityRowToggle(
                systemImage: isLocked ? "lock.fill" : "lock.open",
                tint: isLocked ? .editorTextPrimary : .editorTextTertiary,
                help: isLocked ? "Unlock: the viewport can select and move it again" : "Lock: the viewport cannot select or move it"
            ) {
                selectionManager.toggleLocked(entityid)
            }
        }
    }

    private var textColor: Color {
        if isDimmed {
            return .editorTextDisabled
        }
        if isSelected {
            return .editorTextSelected
        }
        return isAssetNode ? .editorTextSecondary : .editorTextPrimary
    }

    private var iconColor: Color {
        if isDimmed {
            return .editorTextDisabled
        }
        return isSelected ? .editorTextSelected : .editorTextTertiary
    }
}
