//
//  GizmoPalette.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import simd

/// The colours of the transform gizmo, from the redesign spec: red for X,
/// green for Y, blue for Z and a white centre.
///
/// The spec names them as they look on the screen. The gizmo is drawn into
/// the scene before the tone map and the display's curve, so each is handed to
/// the engine as the light that curve turns back into the colour.
enum GizmoPalette {
    static let x = linear(hex: 0xFF5A5A)
    static let y = linear(hex: 0x5CE08C)
    static let z = linear(hex: 0x4C8DFF)
    static let center = linear(hex: 0xFFFFFF)

    /// The engine keeps a gizmo's pixel only when it is brighter than this,
    /// by the weights below; a darker colour would not be drawn at all.
    static let engineLuminanceFloor: Float = 0.1

    /// The light of a colour written as `0xRRGGBB` for the screen.
    static func linear(hex: UInt32) -> simd_float4 {
        simd_float4(
            linear(fromDisplay: Float((hex >> 16) & 0xFF) / 255),
            linear(fromDisplay: Float((hex >> 8) & 0xFF) / 255),
            linear(fromDisplay: Float(hex & 0xFF) / 255),
            1
        )
    }

    /// The sRGB curve, from what the screen shows to the light behind it.
    static func linear(fromDisplay value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    /// How bright the engine takes a colour to be when it decides whether a
    /// pixel is the gizmo's.
    static func engineLuminance(of color: simd_float4) -> Float {
        simd_dot(simd_float3(color.x, color.y, color.z), simd_float3(0.299, 0.587, 0.114))
    }
}
