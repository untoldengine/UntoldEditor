//
//  EditorView+ViewportControls.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
import SwiftUI
import UntoldEngine

extension EditorView {
    /// The header of the viewport panel, fed from the viewport settings.
    var viewportHeader: some View {
        ViewportHeaderView(
            settings: viewportSettings,
            snap: EditorSnapSettings.shared,
            onSelectTool: editor_selectTool,
            onSelectSpace: editor_selectSpace,
            onSelectShading: editor_selectShading,
            onSelectProjection: editor_selectProjection
        )
    }

    /// Picks a tool: the selection's gizmo follows it, and a drag in progress ends.
    func editor_selectTool(_ tool: TransformTool) {
        viewportSettings.tool = tool
        editorController?.activeMode = .none
        selectionManager.refreshGizmo()
    }

    /// World or Local: the gizmo turns to the axes it will work along.
    func editor_selectSpace(_ space: TransformSpace) {
        viewportSettings.transformSpace = space
        syncGizmoOrientation()
    }

    func editor_selectShading(_ option: TextureDebugOption) {
        viewportSettings.show(option)
    }

    /// Applies the persisted shading when the editor starts.
    func editor_applyViewportSettings() {
        viewportSettings.show(viewportSettings.shading)
    }

    /// Sends the editor's camera to a preset view, which also ends a preview
    /// of a game camera. Not while playing, when the play flow owns the camera.
    func editor_selectProjection(_ projection: ViewportProjection) {
        guard isPlaying == false else { return }
        viewportSettings.projection = projection
        projection.applyToSceneCamera()
        viewportSettings.camera = .editor
    }

    /// View > Camera: shows the editor's camera, or a game camera of the scene
    /// as a locked preview. Not during a play session, when the play flow owns
    /// the camera.
    func editor_showViewportCamera(_ camera: ViewportCamera) {
        guard experienceMode == .edit, isPlaying == false, ViewportCameras.show(camera) else { return }
        viewportSettings.camera = camera
    }

    /// True while the viewport shows the editor's camera for editing, when
    /// the editor draws its overlays over the scene: not in explore mode, not
    /// while playing and not over the locked preview of a game camera.
    var editor_showsViewportOverlays: Bool {
        experienceMode == .edit && isPlaying == false && ViewportCameras.isLockedPreview == false
    }

    /// The game camera the viewport is locked on, for its label; nil on the
    /// editor's camera and during a play session.
    var editor_previewedCamera: GameCameraChoice? {
        guard isPlaying == false, case let .game(entityId) = ViewportCameras.current else { return nil }
        return ViewportCameras.gameCameras().first { $0.entityId == entityId }
    }

    /// F: frames the selection, keeping the camera's direction.
    func editor_frameSelection() {
        guard experienceMode == .edit, isPlaying == false, ViewportCameras.isLockedPreview == false,
              let bounds = selectionManager.selectionFramingBounds()
        else { return }
        let camera = findSceneCamera()
        let forward = getCameraTarget(entityId: camera) - getCameraEye(entityId: camera)
        let framing = ViewportFraming.framing(minimum: bounds.min, maximum: bounds.max, forward: forward, fovDegrees: fov)
        cameraLookAt(entityId: camera, eye: framing.eye, target: framing.target, up: getCameraUp(entityId: camera))
        setOrbitOffset(entityId: camera, uTargetOffset: framing.distance)
    }
}
