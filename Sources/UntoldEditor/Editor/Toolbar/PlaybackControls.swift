//
//  PlaybackControls.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The Play / Pause / Step pill in the middle of the toolbar. Play lights up
/// for the whole play session and stops it when pressed again; Pause lights up
/// while paused and resumes; Step waits for an engine frame step.
struct PlaybackControls: View {
    let state: EditorPlayState
    /// True while a post-Play restore is in flight, which must not be interrupted.
    var isBusy = false
    /// False outside the full editor (the welcome and explore screens).
    var isAvailable = true
    let onPlayStop: () -> Void
    let onPauseResume: () -> Void
    let onStep: () -> Void

    var body: some View {
        EditorPillGroup {
            EditorPillButton(
                systemImage: "play.fill",
                isActive: state.isInSession,
                isEnabled: isAvailable && isBusy == false,
                help: state.playButtonStops ? "Stop play mode and restore the scene" : "Enter play mode",
                action: onPlayStop
            )
            EditorPillButton(
                systemImage: "pause.fill",
                isActive: state == .paused,
                isEnabled: isAvailable && isBusy == false && state.isInSession,
                help: state.pauseButtonResumes ? "Resume" : "Pause the running scene",
                action: onPauseResume
            )
            EditorPillButton(
                systemImage: "forward.frame.fill",
                isEnabled: isAvailable && state.canStep,
                help: "Step one frame (waits for an engine frame step, phase 2 of the redesign)",
                action: onStep
            )
        }
    }
}
