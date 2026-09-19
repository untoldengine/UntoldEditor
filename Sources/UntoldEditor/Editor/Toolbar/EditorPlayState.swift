//
//  EditorPlayState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The editor's play session as the toolbar sees it. `editing` is the normal
/// state. Play snapshots the scene and opens a session (`playing`). Pause keeps
/// the session and its snapshot but stops the engine's update (`paused`). Stop
/// closes the session and restores the snapshot.
enum EditorPlayState: Equatable {
    case editing
    case playing
    case paused

    /// The state for the two flags the root view keeps.
    static func resolve(isPlaying: Bool, isPaused: Bool) -> EditorPlayState {
        guard isPlaying else {
            return .editing
        }
        return isPaused ? .paused : .playing
    }

    /// Whether a play session is open, paused or not.
    var isInSession: Bool {
        self != .editing
    }

    /// What the Play button does: open a session, or stop the open one.
    var playButtonStops: Bool {
        isInSession
    }

    /// The Pause button pauses while playing and resumes while paused.
    var pauseButtonResumes: Bool {
        self == .paused
    }

    /// Stepping one frame needs an engine API (`stepFrame`, phase 2 of the
    /// redesign plan); until it exists the Step button is drawn disabled.
    static let stepIsAvailable = false

    var canStep: Bool {
        self == .paused && Self.stepIsAvailable
    }
}
