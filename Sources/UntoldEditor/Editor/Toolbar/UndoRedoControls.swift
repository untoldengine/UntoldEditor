//
//  UndoRedoControls.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The Undo / Redo / History pill of the toolbar, over the editor's undo manager.
/// History opens a popover that lists the undoable and redoable actions.
struct UndoRedoControls: View {
    @ObservedObject private var undoManager = EditorUndoManager.shared
    @State private var showHistory = false

    init() {}

    var body: some View {
        EditorPillGroup {
            EditorPillButton(
                systemImage: "arrow.uturn.backward",
                isEnabled: undoManager.canUndo,
                help: "Undo (⌘Z)"
            ) {
                undoManager.undo()
            }
            EditorPillButton(
                systemImage: "arrow.uturn.forward",
                isEnabled: undoManager.canRedo,
                help: "Redo (⇧⌘Z)"
            ) {
                undoManager.redo()
            }
            EditorPillMenuButton(
                title: "History",
                isEnabled: hasHistory,
                help: "Show the actions that can be undone or redone"
            ) {
                showHistory.toggle()
            }
            .popover(isPresented: $showHistory, arrowEdge: .bottom) {
                UndoHistoryPopover(undoManager: undoManager) {
                    showHistory = false
                }
            }
        }
    }

    private var hasHistory: Bool {
        undoManager.canUndo || undoManager.canRedo
    }
}
