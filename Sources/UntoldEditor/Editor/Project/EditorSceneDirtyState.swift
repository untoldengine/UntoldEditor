//
//  EditorSceneDirtyState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Tracks whether the active scene has changes that haven't been saved to disk.
/// A monotonic latch, not derived from the undo stack: any mutation marks it
/// dirty, and only a confirmed-successful save (or loading/creating a scene
/// whose in-memory content now exactly matches disk) clears it. Undo/redo
/// landing back at the exact saved state does NOT clear it.
final class EditorSceneDirtyState: ObservableObject {
    static let shared = EditorSceneDirtyState()

    @Published private(set) var isDirty = false
    /// When the editor last wrote the scene to disk; nil after a load, or for a
    /// scene that was never saved. The status bar shows it.
    @Published private(set) var lastSavedAt: Date?

    private init() {}

    func markDirty() {
        isDirty = true
    }

    func clear() {
        isDirty = false
        lastSavedAt = nil
    }

    /// A save just succeeded: clean, and stamped for the status bar.
    func markSaved(at date: Date = Date()) {
        isDirty = false
        lastSavedAt = date
    }
}
