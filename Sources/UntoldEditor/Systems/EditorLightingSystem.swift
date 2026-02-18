//
//  EditorLightingSystem.swift
//  UntoldEngine
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import UntoldEngine

private func makeSpotLightDebugMesh() -> [Mesh] {
    BasicPrimitives.createCone(height: 1.0, radius: 0.5, segments: [24, 1])
}

private func makeAreaLightDebugMesh() -> [Mesh] {
    BasicPrimitives.createPlane(width: 1.0, depth: 1.0, segments: [1, 1])
}

private func makePointLightDebugMesh() -> [Mesh] {
    BasicPrimitives.createSphere(extent: 0.25, segments: [24, 12])
}

private func makeDirectionalLightDebugMesh() -> [Mesh] {
    BasicPrimitives.createSphere(extent: 0.25, segments: [24, 12])
}

func loadLightDebugMeshes() {
    spotLightDebugMesh = makeSpotLightDebugMesh()

    pointLightDebugMesh = makePointLightDebugMesh()

    areaLightDebugMesh = makeAreaLightDebugMesh()

    dirLightDebugMesh = makeDirectionalLightDebugMesh()
}
