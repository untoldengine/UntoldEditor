//
//  MaterialSphereView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A lit sphere in the material's colour: a fixed light from the top left, a
/// highlight that spreads with roughness and strengthens with metallic, the
/// emission lifting the shadow, the opacity fading it all. Drawn, not rendered.
struct MaterialSphereView: View {
    let baseColor: Color
    let roughness: Float
    let metallic: Float
    let emission: Float
    let opacity: Float
    var size: CGFloat = 64

    var body: some View {
        let shading = Self.shading(roughness: roughness, metallic: metallic)
        let shadow = Double(max(0, 0.7 - max(0, min(1, emission)) * 0.5))
        ZStack {
            Circle()
                .fill(baseColor)
            Circle()
                .fill(RadialGradient(
                    colors: [Color.clear, Color.black.opacity(shadow)],
                    center: UnitPoint(x: 0.35, y: 0.3),
                    startRadius: size * 0.1,
                    endRadius: size * 0.65
                ))
            Circle()
                .fill(Color.white.opacity(shading.highlightOpacity))
                .frame(width: size * shading.highlightSize, height: size * shading.highlightSize)
                .blur(radius: size * shading.highlightBlur)
                .offset(x: -size * 0.18, y: -size * 0.2)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.editorHairline, lineWidth: 1))
        .opacity(0.3 + Double(max(0, min(1, opacity))) * 0.7)
    }

    /// The highlight for a roughness and a metallic amount: its size and blur
    /// as fractions of the sphere, and its opacity.
    static func shading(roughness: Float, metallic: Float) -> (highlightSize: CGFloat, highlightOpacity: Double, highlightBlur: CGFloat) {
        let rough = CGFloat(max(0, min(1, roughness)))
        let metal = Double(max(0, min(1, metallic)))
        return (
            highlightSize: 0.18 + rough * 0.5,
            highlightOpacity: 0.85 - Double(rough) * 0.55 + metal * 0.1,
            highlightBlur: 0.02 + rough * 0.12
        )
    }
}
