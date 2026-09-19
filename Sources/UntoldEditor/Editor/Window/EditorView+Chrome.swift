//
//  EditorView+Chrome.swift
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
    /// The toolbar row under the title bar, fed from the root view's state.
    var editorToolbar: some View {
        EditorToolbarView(
            projectName: editorBasePath.projectName,
            playState: EditorPlayState.resolve(isPlaying: isPlaying, isPaused: isPaused),
            isPlayBusy: isRestoringPlayMode,
            playIsAvailable: experienceMode == .edit,
            buildTarget: $buildTargetSettings.target,
            onSelectProject: { selectionManager.selectProject() },
            onPlayStop: { editor_handlePlayToggle(!isPlaying) },
            onPauseResume: editor_togglePauseInPlayMode,
            onStep: {}
        )
    }

    /// The status bar along the bottom of the window.
    var editorStatusBar: some View {
        EditorStatusBarView(
            entityCount: editor_entities.count,
            hasSceneFile: editorController?.currentSceneURL != nil,
            isRestoringPlayMode: isRestoringPlayMode
        )
    }
}
