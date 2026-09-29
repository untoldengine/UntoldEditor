//
//  CameraPlacement.swift
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

/// Where a camera stands and looks, to put it back there: what its last
/// look-at left, and its place and turn now, which flying moves on from the
/// look-at.
struct CameraPlacement: Equatable {
    var eye: simd_float3
    var target: simd_float3
    var up: simd_float3
    var position: simd_float3
    var rotation: simd_quatf

    /// The placement of a camera now; nil for an entity that is no camera.
    static func capture(of entityId: EntityID) -> CameraPlacement? {
        guard let camera = scene.get(component: CameraComponent.self, for: entityId) else {
            return nil
        }
        return CameraPlacement(
            eye: getCameraEye(entityId: entityId),
            target: getCameraTarget(entityId: entityId),
            up: getCameraUp(entityId: entityId),
            position: camera.localPosition,
            rotation: camera.rotation
        )
    }

    /// Puts a camera where the placement was taken.
    func apply(to entityId: EntityID) {
        guard scene.get(component: CameraComponent.self, for: entityId) != nil else {
            return
        }
        // A camera that never looked at anything has no up to look along.
        if simd_length(up) > 0.0001, simd_length(target - eye) > 0.0001 {
            cameraLookAt(entityId: entityId, eye: eye, target: target, up: up)
        }
        translateTo(entityId: entityId, position: position)
        rotateTo(entityId: entityId, rotation: rotation)
    }
}
