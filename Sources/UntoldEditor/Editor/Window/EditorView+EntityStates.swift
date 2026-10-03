//
//  EditorView+EntityStates.swift
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

extension EditorView {
    /// H: hides the selected entity, the row the hierarchy shows selected, with
    /// everything under it. With nothing selected, nothing happens, and
    /// while the game plays the key is the game's.
    func editor_hideSelectedEntity() {
        guard experienceMode == .edit, isPlaying == false,
              let selected = selectionManager.selectedEntity, selected != .invalid
        else { return }
        selectionManager.setHidden(selected, true)
    }

    /// ⌥H: shows every hidden entity again.
    func editor_showAllEntities() {
        guard experienceMode == .edit, isPlaying == false else { return }
        selectionManager.showAllEntities()
    }
}
