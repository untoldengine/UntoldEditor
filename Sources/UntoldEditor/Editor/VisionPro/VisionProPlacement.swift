//
//  VisionProPlacement.swift
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

/// Where the headset stands in the scene. ARKit measures the headset from
/// its own origin, where its tracking began; the preview puts that origin
/// where it makes the headset, as it stood when the preview began, stand
/// where the editor's camera stood, facing where it faced. Only turns about
/// the vertical axis are used, so the floor stays level.
enum VisionProPlacement {
    /// The turn about the vertical axis that takes the forward direction,
    /// (0, 0, -1), to the level part of `direction`; zero for a direction
    /// straight up or down.
    static func levelYaw(of direction: simd_float3) -> Float {
        guard direction.x * direction.x + direction.z * direction.z > 1e-8 else {
            return 0
        }
        return atan2(-direction.x, -direction.z)
    }

    /// Where a camera stands and faces, from the two fields every way of
    /// steering it writes: its position and its rotation. The camera's `eye`
    /// and `target` are written by `cameraLookAt` alone, so the fly keys and
    /// the mouse leave them behind. Nil for an entity that is no camera.
    static func pose(of camera: EntityID) -> (eye: simd_float3, forward: simd_float3)? {
        guard let component = scene.get(component: CameraComponent.self, for: camera) else {
            return nil
        }
        // The camera looks down its own -Z; its rotation is the view's, from
        // the world into the camera, so the inverse carries -Z out.
        return (component.localPosition, simd_act(simd_conjugate(component.rotation), simd_float3(0, 0, -1)))
    }

    /// The transform that carries the headset's own coordinates into the
    /// scene's: the headset where it was, `originFromDevice`, lands on
    /// `cameraEye` facing the level part of `cameraForward`.
    static func sceneFromOrigin(
        cameraEye: simd_float3,
        cameraForward: simd_float3,
        originFromDevice: simd_float4x4
    ) -> simd_float4x4 {
        let devicePosition = simd_float3(originFromDevice.columns.3.x, originFromDevice.columns.3.y, originFromDevice.columns.3.z)
        // The headset looks down its own -Z.
        let deviceForward = -simd_float3(originFromDevice.columns.2.x, originFromDevice.columns.2.y, originFromDevice.columns.2.z)
        let turn = simd_quatf(angle: levelYaw(of: cameraForward) - levelYaw(of: deviceForward), axis: simd_float3(0, 1, 0))
        return simd_mul(
            simd_mul(matrix4x4Translation(cameraEye.x, cameraEye.y, cameraEye.z), simd_float4x4(turn)),
            matrix4x4Translation(-devicePosition.x, -devicePosition.y, -devicePosition.z)
        )
    }
}
