//
//  EditorView+PlayMode.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    func editor_handlePlayToggle(_ isPlaying: Bool) {
        setEditorPlayMode(isPlaying)
    }

    /// `capturesSnapshot` gates whether Play/Stop takes part in the snapshot/revert
    /// flow at all. Explore Navigation Mode (Welcome/demo-gallery flythrough) also
    /// flips `gameMode` through this same function but is camera navigation only,
    /// not scene editing, so it opts out and keeps its original behavior.
    func setEditorPlayMode(_ shouldPlay: Bool, capturesSnapshot: Bool = true) {
        guard isRestoringPlayMode == false else { return }

        // Play while paused resumes the session instead of opening a new one.
        if shouldPlay, isPlaying, isPaused {
            editor_togglePauseInPlayMode()
            return
        }
        isPaused = false

        let didChangePlayState = isPlaying != shouldPlay || gameMode != shouldPlay
        guard didChangePlayState else {
            isPlaying = shouldPlay
            gameMode = shouldPlay
            updateActiveCameraForPlayMode()
            AnimationSystem.shared.isEnabled = shouldPlay
            return
        }

        if shouldPlay {
            if capturesSnapshot {
                playModeSnapshot = serializeScene()
            }
            isPlaying = true
            gameMode = true
            updateActiveCameraForPlayMode()
            AnimationSystem.shared.isEnabled = true
            USCSystem.shared.startPlayMode()
            ComponentLibraryController.shared.playModeDidStart()
        } else {
            isPlaying = false
            gameMode = false
            AnimationSystem.shared.isEnabled = false
            USCSystem.shared.stopPlayMode()
            // A library built during play waits for the snapshot restore below before it loads.
            ComponentLibraryController.shared.playModeDidStop(restoring: capturesSnapshot && playModeSnapshot != nil)
            // Active-camera fixup is deliberately NOT done here: if a restore is about
            // to run, it must target the restored entities (new IDs), not the
            // about-to-be-destroyed drifted ones. beginPlayModeRestore's completion
            // handles it instead; the legacy fallback below handles the no-restore case.
            if capturesSnapshot, let snapshot = playModeSnapshot {
                beginPlayModeRestore(from: snapshot)
            } else {
                updateActiveCameraForPlayMode()
            }
        }
    }

    /// Reverts Play-mode drift (physics/animation/USC-script mutations) by wiping
    /// the world and reloading the exact pre-Play snapshot. Mirrors the same
    /// destroy+deserialize sequence used by `editor_handleLoad`/`editor_loadScene`.
    /// Entity IDs are not stable across this cycle (the engine always allocates
    /// fresh IDs on deserialize), so the undo stack and editor-side per-entity
    /// state are cleared along with it — entering Play mode is an accepted
    /// "undo checkpoint" boundary.
    func beginPlayModeRestore(from snapshot: SceneData) {
        isRestoringPlayMode = true
        playModeSnapshot = nil

        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()
        EditorGaussianAssetState.shared.clear()
        EditorUndoManager.shared.clear()
        sceneAuthoredGameCamera = nil

        deserializeScene(sceneData: snapshot, onGaussianEntityRestored: restoreEditorGaussianState) {
            NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
            editor_entities = getAllGameEntities()
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            gizmoActive = false
            selectionManager.objectWillChange.send()
            sceneGraphModel.refreshHierarchy()

            CameraSystem.shared.activeCamera = findSceneCamera()
            updateActiveCameraForPlayMode()

            isRestoringPlayMode = false
            ComponentLibraryController.shared.playModeRestoreDidFinish()
        }
    }

    /// Pause keeps the play session and its snapshot but stops the engine's
    /// update, so physics, animation and scripts freeze while the frame keeps
    /// rendering. A second call resumes.
    func editor_togglePauseInPlayMode() {
        guard isPlaying, isRestoringPlayMode == false else { return }
        isPaused.toggle()
        gameMode = isPaused == false
        AnimationSystem.shared.isEnabled = isPaused == false
    }

    func enableExploreNavigationMode() {
        playbackSettings.useSceneCameraDuringPlay = true
        setEditorPlayMode(true, capturesSnapshot: false)
        CameraSystem.shared.activeCamera = findSceneCamera()
    }

    func disableExploreNavigationMode() {
        if isPlaying {
            setEditorPlayMode(false, capturesSnapshot: false)
        }
    }

    func updateActiveCameraForPlayMode() {
        // The session, not `gameMode`: a paused session keeps the game camera.
        if isPlaying {
            CameraSystem.shared.activeCamera = playbackSettings.useSceneCameraDuringPlay ? findSceneCamera() : findEditorGameCamera()
        } else {
            CameraSystem.shared.activeCamera = findSceneCamera()
        }
    }
}
