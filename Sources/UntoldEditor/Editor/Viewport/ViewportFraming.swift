//
//  ViewportFraming.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd

/// The camera placement that frames the selection (F).
enum ViewportFraming {
    /// Looks along `forward` at the centre of the box from far enough that its
    /// bounding sphere fits the vertical field of view, `fovDegrees`, with a
    /// little room around it.
    static func framing(minimum: simd_float3, maximum: simd_float3, forward: simd_float3, fovDegrees: Float) -> (eye: simd_float3, target: simd_float3, distance: Float) {
        let center = (minimum + maximum) / 2
        let radius = max(simd_length(maximum - minimum) / 2, 0.01)
        let halfFov = max(fovDegrees, 1) * .pi / 360
        let distance = radius / tan(halfFov) * 1.1
        let direction = simd_length(forward) > 0.0001 ? simd_normalize(forward) : simd_float3(0, 0, -1)
        return (center - direction * distance, center, distance)
    }
}
