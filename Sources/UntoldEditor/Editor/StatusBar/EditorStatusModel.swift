//
//  EditorStatusModel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The strings of the status bar, computed from the engine's stats snapshot and
/// the editor's state. Pure functions, so the formatting is testable without a
/// running engine.
enum EditorStatusModel {
    struct Readiness: Equatable {
        let label: String
        let isBusy: Bool
    }

    struct SaveState: Equatable {
        let label: String
        let isUnsaved: Bool
    }

    /// "Ready" with a green dot, or what the editor is busy with.
    static func readiness(activeTasks: Int, isRestoringPlayMode: Bool) -> Readiness {
        if isRestoringPlayMode {
            return Readiness(label: "Restoring scene", isBusy: true)
        }
        if activeTasks > 0 {
            let noun = activeTasks == 1 ? "task" : "tasks"
            return Readiness(label: "\(activeTasks) \(noun) running", isBusy: true)
        }
        return Readiness(label: "Ready", isBusy: false)
    }

    /// Frames per second from the engine's smoothed frame time; a dash while the
    /// engine reports nothing (no scene, or a build without engine stats).
    static func fps(frameMs: Double) -> String {
        guard frameMs > 0 else {
            return "— fps"
        }
        return "\(Int((1000 / frameMs).rounded())) fps"
    }

    static func drawCalls(_ count: Int) -> String {
        count == 1 ? "1 draw call" : "\(count) draw calls"
    }

    static func entities(_ count: Int) -> String {
        count == 1 ? "1 entity" : "\(count) entities"
    }

    /// Mesh and texture memory the engine tracks, in megabytes.
    static func gpuMemory(bytes: Int) -> String {
        guard bytes > 0 else {
            return "GPU —"
        }
        let megabytes = Double(bytes) / 1_048_576
        if megabytes < 10 {
            return String(format: "GPU %.1f MB", megabytes)
        }
        return String(format: "GPU %.0f MB", megabytes)
    }

    static func lastAction(_ name: String?) -> String {
        "Last action: \(name ?? "none")"
    }

    /// The scene's save state: unsaved edits win, then the time of the last save,
    /// then whether the scene has a file at all.
    static func saveState(isDirty: Bool, hasSceneFile: Bool, lastSavedAt: Date?) -> SaveState {
        if isDirty {
            return SaveState(label: "Unsaved changes", isUnsaved: true)
        }
        if let lastSavedAt {
            return SaveState(label: "Saved \(timeFormatter.string(from: lastSavedAt))", isUnsaved: false)
        }
        return SaveState(label: hasSceneFile ? "Saved" : "Not saved yet", isUnsaved: hasSceneFile == false)
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
