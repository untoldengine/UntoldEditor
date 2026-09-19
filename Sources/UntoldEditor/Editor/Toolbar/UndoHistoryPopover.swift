//
//  UndoHistoryPopover.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The list behind the toolbar's History button: the actions that can be undone,
/// most recent first, then the ones that can be redone. Clicking an entry undoes
/// or redoes up to and including it.
struct UndoHistoryPopover: View {
    @ObservedObject var undoManager: EditorUndoManager
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if undoManager.undoHistory.isEmpty == false {
                sectionTitle("Undo")
                ForEach(Array(undoManager.undoHistory.enumerated()), id: \.offset) { index, name in
                    EditorPopupMenuRow(title: name, shortcut: index == 0 ? "⌘Z" : nil) {
                        undoManager.undo(steps: index + 1)
                        onDone()
                    }
                }
            }
            if undoManager.redoHistory.isEmpty == false {
                sectionTitle("Redo")
                ForEach(Array(undoManager.redoHistory.enumerated()), id: \.offset) { index, name in
                    EditorPopupMenuRow(title: name, shortcut: index == 0 ? "⇧⌘Z" : nil) {
                        undoManager.redo(steps: index + 1)
                        onDone()
                    }
                }
            }
            if undoManager.undoHistory.isEmpty, undoManager.redoHistory.isEmpty {
                Text("Nothing to undo")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextTertiary)
                    .padding(8)
            }
        }
        .padding(6)
        .frame(width: 260)
        .background(Color.editorPanelBackground)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(EditorType.badge)
            .foregroundColor(.editorTextTertiary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}
