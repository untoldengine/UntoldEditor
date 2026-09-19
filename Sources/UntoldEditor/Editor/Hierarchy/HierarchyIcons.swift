//
//  HierarchyIcons.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldEngine

/// Icon for a hierarchy row. Lights map to their primitive (matching the Add
/// menu); asset nodes keep their asset icons. The engine doesn't store which
/// mesh primitive an entity is, so everything else falls back to a cube.
func hierarchyIconName(for entityId: EntityID) -> String {
    if hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self) {
        return "sun.max"
    }
    if hasComponent(entityId: entityId, componentType: PointLightComponent.self) {
        return "lightbulb"
    }
    if hasComponent(entityId: entityId, componentType: SpotLightComponent.self) {
        return "flashlight.on.fill"
    }
    if hasComponent(entityId: entityId, componentType: AreaLightComponent.self) {
        return "square"
    }
    if isDerivedAssetNode(entityId) {
        return isBindableAssetMeshNode(entityId) ? "cube.fill" : "square.stack.3d.up"
    }
    return "cube"
}
