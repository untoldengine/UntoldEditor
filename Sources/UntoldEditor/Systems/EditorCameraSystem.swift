//
//  EditorCameraSystem.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import UntoldEngine

public func findSceneCamera() -> EntityID {
    for entityId in scene.getAllEntities() {
        if hasComponent(entityId: entityId, componentType: CameraComponent.self), hasComponent(entityId: entityId, componentType: SceneCameraComponent.self) {
            return entityId
        }
    }

    // if scene camera was not found, then create one

    let sceneCamera = createEntity()
    createSceneCamera(entityId: sceneCamera)
    return sceneCamera
}

public func createSceneCamera(entityId: EntityID) {
    setEntityName(entityId: entityId, name: "Scene Camera")
    registerComponent(entityId: entityId, componentType: CameraComponent.self)
    registerComponent(entityId: entityId, componentType: SceneCameraComponent.self)

    cameraLookAt(entityId: entityId,
                 eye: cameraDefaultEye, target: cameraTargetDefault,
                 up: cameraUpDefault)
}
