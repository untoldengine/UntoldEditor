//
//  MaterialSnapshot.swift
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

/// The values the Material block edits, copied from one mesh to paste into
/// another, and the arithmetic behind its controls.
struct MaterialSnapshot: Equatable {
    var baseColor: simd_float4
    var roughness: Float
    var metallic: Float
    var emissive: simd_float3
    var opacity: Float

    init(baseColor: simd_float4, roughness: Float, metallic: Float, emissive: simd_float3, opacity: Float) {
        self.baseColor = baseColor
        self.roughness = roughness
        self.metallic = metallic
        self.emissive = emissive
        self.opacity = opacity
    }

    init(entityId: EntityID, meshIndex: Int) {
        baseColor = getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)
        roughness = getMaterialRoughness(entityId: entityId, meshIndex: meshIndex)
        metallic = getMaterialMetallic(entityId: entityId, meshIndex: meshIndex)
        emissive = getMaterialEmmissive(entityId: entityId, meshIndex: meshIndex)
        opacity = getMaterialOpacity(entityId: entityId, meshIndex: meshIndex)
    }

    func apply(to entityId: EntityID, meshIndex: Int) {
        updateMaterialColor(entityId: entityId, color: colorFromSimd(baseColor), meshIndex: meshIndex)
        updateMaterialRoughness(entityId: entityId, roughness: roughness, meshIndex: meshIndex)
        updateMaterialMetallic(entityId: entityId, metallic: metallic, meshIndex: meshIndex)
        updateMaterialEmmisive(entityId: entityId, emmissive: emissive, meshIndex: meshIndex)
        updateMaterialOpacity(entityId: entityId, opacity: opacity, meshIndex: meshIndex, submeshIndex: 0)
    }

    /// "#5CE08C" for a colour's red, green and blue.
    static func hex(_ color: simd_float4) -> String {
        func channel(_ value: Float) -> Int {
            Int((max(0, min(1, value)) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", channel(color.x), channel(color.y), channel(color.z))
    }

    /// The Emission slider's value for an emissive colour: its brightest channel.
    static func emissionStrength(of emissive: simd_float3) -> Float {
        max(emissive.x, max(emissive.y, emissive.z))
    }

    /// The emissive colour for a new slider value: the current colour scaled to
    /// that strength, or the base colour at that strength when it was black, so
    /// the slider brightens what is there instead of turning it white. A black
    /// base colour glows neutral.
    static func emissive(forStrength strength: Float, current: simd_float3, baseColor: simd_float4) -> simd_float3 {
        let currentStrength = emissionStrength(of: current)
        if currentStrength > 0 {
            return current * (strength / currentStrength)
        }
        let base = simd_float3(baseColor.x, baseColor.y, baseColor.z)
        let baseStrength = emissionStrength(of: base)
        return baseStrength > 0 ? base * (strength / baseStrength) : simd_float3(repeating: strength)
    }
}
