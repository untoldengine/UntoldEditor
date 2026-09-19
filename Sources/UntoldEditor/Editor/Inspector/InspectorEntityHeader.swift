//
//  InspectorEntityHeader.swift
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

/// The top of the Inspector for an entity: its type icon, its name (editable,
/// one undo step per edit), the dot that shows and hides it, and the pin that
/// keeps the Inspector on it while the selection changes.
struct InspectorEntityHeader: View {
    let entityId: EntityID
    @ObservedObject var selectionManager: SelectionManager
    /// Called once a name edit is committed, after it is on the undo stack.
    let onNameCommitted: () -> Void

    @FocusState private var isNameFocused: Bool
    @State private var nameEditStartValue: String?

    private var isHidden: Bool {
        selectionManager.isEffectivelyHidden(entityId)
    }

    private var isPinned: Bool {
        selectionManager.pinnedInspection == entityId
    }

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.editorAccent, lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: hierarchyIconName(for: entityId))
                        .font(.system(size: 9))
                        .foregroundColor(.editorAccent)
                }

            TextField("Entity name", text: nameBinding)
                .textFieldStyle(.plain)
                .font(EditorType.title)
                .foregroundColor(.editorTextPrimary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(Color.editorControlFill)
                .cornerRadius(EditorType.Radius.field)
                .focused($isNameFocused)
                .onSubmit {
                    commitName()
                    isNameFocused = false
                }
                .onChange(of: isNameFocused) { _, isFocused in
                    if isFocused {
                        nameEditStartValue = getEntityName(entityId: entityId)
                    } else {
                        commitName()
                    }
                }

            Button {
                selectionManager.toggleHidden(entityId)
            } label: {
                Circle()
                    .fill(isHidden ? Color.editorTextDisabled : Color.editorSuccess)
                    .frame(width: 8, height: 8)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isHidden ? "Hidden in the viewport. Click to show it." : "Shown in the viewport. Click to hide it.")

            Button {
                selectionManager.togglePinnedInspection(entityId)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(isPinned ? .editorAccent : .editorTextTertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(isPinned ? "Unpin: the Inspector follows the selection again" : "Pin: keep showing this entity while the selection changes")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { getEntityName(entityId: entityId) },
            set: { setEntityName(entityId: entityId, name: $0) }
        )
    }

    private func commitName() {
        guard let oldName = nameEditStartValue else { return }
        nameEditStartValue = nil
        EditorUndoManager.shared.registerNameChange(entityId: entityId, oldName: oldName, newName: getEntityName(entityId: entityId))
        onNameCommitted()
    }
}
