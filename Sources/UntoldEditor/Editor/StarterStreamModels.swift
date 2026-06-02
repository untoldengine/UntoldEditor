//
//  StarterStreamModels.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
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

let starterStreamModels: [StreamModelCatalogItem] = [
    .init(
        id: "dungeon",
        title: "Game Dungeon",
        manifestURL: URL(string: "https://d8pyi1c08k1w.cloudfront.net/dungeon3/dungeon3.json")!
    ),
    .init(
        id: "city",
        title: "Cartoon City",
        manifestURL: URL(string: "https://d8pyi1c08k1w.cloudfront.net/city/city.json")!
    ),
    .init(
        id: "f1car",
        title: "Formula 1",
        manifestURL: URL(string: "https://d8pyi1c08k1w.cloudfront.net/F1Car/F1Car.json")!
    ),
    .init(
        id: "airplane",
        title: "Skyhawk",
        manifestURL: URL(string: "https://d8pyi1c08k1w.cloudfront.net/Shyhawk_stream/Skyhawks.json")!
    ),
    .init(
        id: "porsche964",
        title: "Porsche 964",
        manifestURL: URL(string: "https://d8pyi1c08k1w.cloudfront.net/Porsche964-stream/Porsche964-stream.json")!
    ),
]

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
