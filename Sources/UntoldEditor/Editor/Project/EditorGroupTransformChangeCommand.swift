//
//  EditorGroupTransformChangeCommand.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import UntoldEngine

/// Several entities moved, turned or scaled together by one drag of the
/// gizmo: one step to undo, which puts every one of them back.
struct EditorGroupTransformChangeCommand: EditorUndoCommand {
    struct Change {
        let entityId: EntityID
        let before: EditorTransformSnapshot
        let after: EditorTransformSnapshot
    }

    let changes: [Change]

    var name: String {
        "Transform \(changes.count) Entities"
    }

    func undo() {
        for change in changes {
            change.before.apply(to: change.entityId)
        }
    }

    func redo() {
        for change in changes {
            change.after.apply(to: change.entityId)
        }
    }
}
