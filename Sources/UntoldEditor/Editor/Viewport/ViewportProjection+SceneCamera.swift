//
//  ViewportProjection+SceneCamera.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
import UntoldEngine

extension ViewportProjection {
    /// Puts the viewport on the editor's camera and, for a preset view, sends
    /// that camera along its axis, keeping the pivot and the distance to it.
    /// While editing, the viewport is always the editor's camera: the mouse
    /// and the keys steer it, and the gizmo and the outline are drawn from it.
    func applyToSceneCamera() {
        let camera = findSceneCamera()
        setCamera(.active(camera))

        guard let view else { return }
        // Flying leaves the camera's target where the last look-at put it, so the
        // pivot is taken afresh from what the camera is looking at now.
        InputSystem.shared.reanchorSceneCameraTarget()
        let pivot = getCameraTarget(entityId: camera)
        let distance = max(simd_length(getCameraEye(entityId: camera) - pivot), InputSystem.minimumOrbitPivotDistance)
        cameraLookAt(entityId: camera, eye: pivot + view.direction * distance, target: pivot, up: view.up)
        setOrbitOffset(entityId: camera, uTargetOffset: distance)
    }
}
