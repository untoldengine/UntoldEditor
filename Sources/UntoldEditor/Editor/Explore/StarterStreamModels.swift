//
//  StarterStreamModels.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import simd

struct StreamModelCatalogItem: Identifiable, Hashable {
    let id: String
    let title: String
    let manifestURL: URL
}

struct StreamModelCameraFrame {
    let eye: simd_float3
    let target: simd_float3
    let usesOriginOrbit: Bool
}

/// No streamed demo scenes are hosted; the Explore gallery (unreachable since
/// the editor now launches straight into the full editor) has nothing to list.
let starterStreamModels: [StreamModelCatalogItem] = []

extension StreamModelCatalogItem {
    var cameraFrame: StreamModelCameraFrame {
        switch id {
        case "city":
            StreamModelCameraFrame(
                eye: simd_float3(0.00, 18.35, 73.56),
                target: simd_float3(0.0, 0.0, -2.0),
                usesOriginOrbit: false
            )
        case "f1car":
            StreamModelCameraFrame(
                eye: simd_float3(0.0, 2.0, 6.0),
                target: simd_float3(0.0, 0.0, 0.0),
                usesOriginOrbit: true
            )
        case "airplane":
            StreamModelCameraFrame(
                eye: simd_float3(0.0, 2.0, 3.0),
                target: simd_float3(0.0, 0.0, 0.0),
                usesOriginOrbit: true
            )
        case "porsche964":
            StreamModelCameraFrame(
                eye: simd_float3(0.0, 7.0, 15.0),
                target: simd_float3(0.0, 0.0, 0.0),
                usesOriginOrbit: true
            )
        default:
            StreamModelCameraFrame(
                eye: simd_float3(0.0, 1.0, 4.0),
                target: simd_float3(0.0, 0.0, -2.0),
                usesOriginOrbit: false
            )
        }
    }
}
