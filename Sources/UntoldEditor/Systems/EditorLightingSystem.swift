//
//  EditorLightingSystem.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
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
