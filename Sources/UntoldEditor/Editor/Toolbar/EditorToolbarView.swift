//
//  EditorToolbarView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The toolbar row that shares the window's title bar: the traffic lights on
/// the left (drawn by macOS), the project chip, Undo / Redo / History, the play
/// controls in the middle, and the build target on the right. The search field
/// of the mockup joins it with the command palette (stage 1.9). Global chrome:
/// it shows in every experience mode. Dragging its empty space moves the
/// window, as the title bar it replaces did.
struct EditorToolbarView: View {
    /// Matches the unified title bar the window uses, so the traffic lights sit
    /// centred in the row.
    static let height: CGFloat = 52
    /// Space the window's traffic lights take at the left of the row.
    static let trafficLightInset: CGFloat = 78

    let projectName: String?
    let playState: EditorPlayState
    var isPlayBusy = false
    var playIsAvailable = true
    @Binding var buildTarget: EditorBuildTarget
    let onSelectProject: () -> Void
    let onPlayStop: () -> Void
    let onPauseResume: () -> Void
    let onStep: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: Self.trafficLightInset - 12)
            ProjectChipView(
                projectName: projectName,
                version: AppDelegate.editorVersion,
                onSelect: onSelectProject
            )
            UndoRedoControls()
            Spacer(minLength: 0)
            BuildTargetMenu(target: $buildTarget)
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .overlay {
            PlaybackControls(
                state: playState,
                isBusy: isPlayBusy,
                isAvailable: playIsAvailable,
                onPlayStop: onPlayStop,
                onPauseResume: onPauseResume,
                onStep: onStep
            )
        }
        .background {
            WindowDragRegion()
                .background(Color.editorChromeBackground)
        }
        .overlay(alignment: .bottom) {
            Color.editorHairline
                .frame(height: 1)
        }
    }
}
