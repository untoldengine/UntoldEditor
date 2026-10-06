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
            // A preview on a headset ends before the game takes the camera.
            VisionProPreviewSession.shared.end()
            if capturesSnapshot {
                let snapshot = serializeScene()
                playModeSnapshot = snapshot
                playSessionState = PlaySessionState.capture(saved: snapshot)
                if playsOnTheEditorCamera == false, gameCameraOfTheScene() == nil {
                    Logger.log(message: "Play: the scene has no game camera, so it plays on the editor's.")
                }
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
            // The session is over now, not when a reload completes: the keys
            // and the mouse must not steer the game camera a reload brings
            // back, which the engine makes the active one as it loads.
            playbackSettings.isSessionActive = false
            AnimationSystem.shared.isEnabled = false
            USCSystem.shared.stopPlayMode()

            let snapshot = capturesSnapshot ? playModeSnapshot : nil
            let reasonToLoadAgain = snapshot == nil ? nil : editor_reasonToLoadTheSceneAgain()
            let loadsAgain = snapshot != nil && reasonToLoadAgain != nil
            // A library built during play waits for the snapshot restore below before it loads.
            ComponentLibraryController.shared.playModeDidStop(restoring: loadsAgain)
            // Active-camera fixup is deliberately NOT done here: if a restore is about
            // to run, it must target the restored entities (new IDs), not the
            // about-to-be-destroyed drifted ones. beginPlayModeRestore's completion
            // handles it instead; the other two ways out handle it themselves.
            if let snapshot, let reasonToLoadAgain {
                Logger.log(message: "Play stopped. The scene is loaded again: \(reasonToLoadAgain).")
                beginPlayModeRestore(from: snapshot)
            } else if snapshot != nil {
                finishPlayModeInPlace()
            } else {
                updateActiveCameraForPlayMode()
            }
        }
    }

    /// Why Stop has to load the scene again; nil when the session moved
    /// nothing but where things stand, which is put back in place.
    func editor_reasonToLoadTheSceneAgain() -> PlaySessionState.ReasonToLoadAgain? {
        guard let state = playSessionState else {
            return .cannotBeCompared
        }
        // The scene is saved once more only to be compared. What the
        // serializer has to say about it, it said at Play.
        let logLevel = Logger.logLevel
        Logger.logLevel = .none
        defer { Logger.logLevel = logLevel }
        return state.reasonToLoadAgain(saved: serializeScene())
    }

    /// Ends a play session that moved nothing but where things stand: they
    /// are put back, and the scene is the one from before Play. Its entities
    /// are the same ones, so the selection, the undo history and what is
    /// hidden or locked stay as they were, and nothing is loaded.
    func finishPlayModeInPlace() {
        let restored = playSessionState?.restoreInPlace() ?? 0
        playModeSnapshot = nil
        playSessionState = nil
        Logger.log(message: "Play stopped. The scene was put back in place (\(restored) moved).")

        CameraSystem.shared.activeCamera = findSceneCamera()
        updateActiveCameraForPlayMode()
        selectionManager.refreshGizmo()
        selectionManager.objectWillChange.send()
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
        playSessionState = nil
        // The editor's camera is the editor's, not the scene's: it is where the
        // user was looking, and the scene coming back must not move it.
        let editorCamera = CameraPlacement.capture(of: findSceneCamera())

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
            editorCamera?.apply(to: findSceneCamera())
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

    /// Explore mode flies the editor's camera through the scene, which is play
    /// mode without a snapshot. It leaves View > Use Scene Camera During Play
    /// as the user set it: that choice is for playing while editing.
    func enableExploreNavigationMode() {
        setEditorPlayMode(true, capturesSnapshot: false)
        CameraSystem.shared.activeCamera = findSceneCamera()
    }

    func disableExploreNavigationMode() {
        if isPlaying {
            setEditorPlayMode(false, capturesSnapshot: false)
        }
    }

    /// Whether Play keeps the viewport on the editor's camera: in explore
    /// mode, or by View > Use Scene Camera During Play.
    var playsOnTheEditorCamera: Bool {
        EditorPlaybackSettings.playStaysOnTheEditorCamera(
            isExploring: experienceMode == .explore,
            userChoice: playbackSettings.useSceneCameraDuringPlay
        )
    }

    func updateActiveCameraForPlayMode() {
        playbackSettings.isSessionActive = isPlaying
        EditorUndoManager.shared.playStateDidChange()
        // The session, not `gameMode`: a paused session keeps the game camera.
        // A scene without a game camera plays on the editor's; none is created.
        if isPlaying, playsOnTheEditorCamera == false, let gameCamera = gameCameraOfTheScene() {
            CameraSystem.shared.activeCamera = gameCamera
        } else {
            CameraSystem.shared.activeCamera = findSceneCamera()
        }
    }
}
