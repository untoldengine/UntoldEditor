//
//  VisionProFlight.swift
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

/// How the keys fly the camera the headset rides: level. W and S go along
/// the level part of where the camera faces, A and D to its sides, Q and E
/// straight up and down, at the editor's flying speed. The editor's own
/// flying goes where the camera looks, which with a headset on tilts the
/// floor under the wearer.
enum VisionProFlight {
    struct Keys: Equatable {
        var w = false
        var a = false
        var s = false
        var d = false
        var q = false
        var e = false
    }

    /// The editor flies `speed × 0.1` a frame at 60 frames a second.
    static let unitsPerSecondPerSpeed: Float = 6

    /// The level directions ahead and to the right of a camera facing `forward`.
    static func levelAxes(forward: simd_float3) -> (ahead: simd_float3, right: simd_float3) {
        let yaw = VisionProPlacement.levelYaw(of: forward)
        return (simd_float3(-sin(yaw), 0, -cos(yaw)), simd_float3(cos(yaw), 0, -sin(yaw)))
    }

    /// Where the keys take a camera facing `forward` in `deltaTime` seconds.
    static func displacement(keys: Keys, forward: simd_float3, speed: Float, deltaTime: Float) -> simd_float3 {
        let axes = levelAxes(forward: forward)
        let ahead: Float = (keys.w ? 1 : 0) - (keys.s ? 1 : 0)
        let aside: Float = (keys.d ? 1 : 0) - (keys.a ? 1 : 0)
        let up: Float = (keys.q ? 1 : 0) - (keys.e ? 1 : 0)
        let direction = axes.ahead * ahead + axes.right * aside + simd_float3(0, up, 0)
        return direction * (speed * unitsPerSecondPerSpeed * deltaTime)
    }

    /// Flies `camera` by the keys held, for `deltaTime` seconds.
    static func fly(camera: EntityID, keys: Keys, speed: Float, deltaTime: Float) {
        guard let pose = VisionProPlacement.pose(of: camera) else {
            return
        }
        let delta = displacement(keys: keys, forward: pose.forward, speed: speed, deltaTime: deltaTime)
        guard simd_length_squared(delta) > 0 else {
            return
        }
        cameraMoveBy(entityId: camera, delta: delta, space: .world)
    }
}
