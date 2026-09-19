//
//  EditorView+SceneAuthored.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    func applyCameraFrame(_ frame: StreamModelCameraFrame) {
        let camera = findSceneCamera()

        cameraLookAt(entityId: camera, eye: frame.eye, target: frame.target, up: cameraUpDefault)
        CameraSystem.shared.activeCamera = camera

        if frame.usesOriginOrbit {
            let radius = simd_length(frame.eye - frame.target)
            if radius > 0.001 {
                setOrbitOffset(entityId: camera, uTargetOffset: radius)
            }
        } else {
            setOrbitOffset(entityId: camera, uTargetOffset: 25.0)
        }
    }

    func applyGameCameraFrameToSceneCamera(_ gameCamera: EntityID) {
        let sceneCamera = findSceneCamera()
        let eye = getCameraEye(entityId: gameCamera)
        let up = getCameraUp(entityId: gameCamera)
        let target = getCameraTarget(entityId: gameCamera)

        cameraLookAt(entityId: sceneCamera, eye: eye, target: target, up: up)
        CameraSystem.shared.activeCamera = sceneCamera
    }

    func findEditorGameCamera() -> EntityID {
        let entities = getAllGameEntities()

        if let sceneAuthoredGameCamera,
           entities.contains(sceneAuthoredGameCamera),
           isGameCamera(sceneAuthoredGameCamera)
        {
            return sceneAuthoredGameCamera
        }

        if let activeCamera = CameraSystem.shared.activeCamera,
           entities.contains(activeCamera),
           isGameCamera(activeCamera)
        {
            return activeCamera
        }

        if let existingGameCamera = entities.first(where: isGameCamera) {
            return existingGameCamera
        }

        return findGameCamera()
    }

    func isGameCamera(_ entityId: EntityID) -> Bool {
        hasComponent(entityId: entityId, componentType: CameraComponent.self)
            && hasComponent(entityId: entityId, componentType: SceneCameraComponent.self) == false
    }

    func refreshEditorAfterSceneAuthoredLoad(
        selecting entityId: EntityID?,
        gameCamera: EntityID?
    ) {
        removeGizmo()
        activeEntity = .invalid
        gizmoActive = false
        sceneAuthoredGameCamera = gameCamera
        if let entityId {
            selectionManager.selectedEntity = entityId
        }
        selectionManager.inspectedMesh = nil
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        updateActiveCameraForPlayMode()
        selectionManager.objectWillChange.send()
    }

    func removeDefaultSceneAuthoredEntities(existingEntityIds: Set<EntityID>) {
        let entities = Set(getAllGameEntities())
        let previousSceneAuthoredGameCamera = sceneAuthoredGameCamera
        sceneAuthoredGameCamera = nil

        let gameCamerasToRemove = existingEntityIds.filter {
            entities.contains($0)
                && isGameCamera($0)
                && (getEntityName(entityId: $0) == "Game Camera" || $0 == previousSceneAuthoredGameCamera)
        }

        for gameCameraId in gameCamerasToRemove {
            destroyEntity(entityId: gameCameraId)
            setCamera(.active(.invalid))
        }

        if let directionalLightId = existingEntityIds.first(where: {
            entities.contains($0)
                && getEntityName(entityId: $0) == "Directional Light"
                && hasComponent(entityId: $0, componentType: DirectionalLightComponent.self)
        }) {
            destroyEntity(entityId: directionalLightId)
        }

        sceneGraphModel.refreshHierarchy()
    }

    func findImportedGameCamera(existingEntityIds: Set<EntityID>) -> EntityID? {
        getAllGameEntities().first {
            existingEntityIds.contains($0) == false
                && isGameCamera($0)
        }
    }

    func loadSceneAuthoredPayload(
        filename: String,
        withExtension fileExtension: String,
        selecting entityId: EntityID?,
        sourceName: String
    ) {
        let existingEntityIds = Set(getAllGameEntities())

        loadSceneAuthored(filename: filename, withExtension: fileExtension) { success in
            DispatchQueue.main.async {
                if success {
                    removeDefaultSceneAuthoredEntities(existingEntityIds: existingEntityIds)
                    let importedCamera = findImportedGameCamera(existingEntityIds: existingEntityIds)
                    refreshEditorAfterSceneAuthoredLoad(selecting: entityId, gameCamera: importedCamera)
                    NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
                    EditorSceneDirtyState.shared.markDirty()
                    print("✅ Scene-authored cameras/lights loaded: \(sourceName)")
                } else {
                    print("⚠️ Failed to load scene-authored cameras/lights: \(sourceName)")
                }
            }
        }
    }

    func loadSceneAuthoredPayload(
        url manifestURL: URL,
        selecting entityId: EntityID?,
        sourceName: String
    ) {
        let existingEntityIds = Set(getAllGameEntities())

        loadSceneAuthored(url: manifestURL) { success in
            DispatchQueue.main.async {
                if success {
                    removeDefaultSceneAuthoredEntities(existingEntityIds: existingEntityIds)
                    let importedCamera = findImportedGameCamera(existingEntityIds: existingEntityIds)
                    refreshEditorAfterSceneAuthoredLoad(selecting: entityId, gameCamera: importedCamera)
                    NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
                    EditorSceneDirtyState.shared.markDirty()
                    print("✅ Scene-authored cameras/lights loaded: \(sourceName)")
                } else {
                    print("⚠️ Failed to load scene-authored cameras/lights: \(sourceName)")
                }
            }
        }
    }

    func editor_loadSceneAuthoredFromAsset(_ asset: Asset) {
        let fileExtension = asset.path.pathExtension.lowercased()

        if fileExtension == "untold" {
            loadSceneAuthoredPayload(
                filename: asset.path.path,
                withExtension: fileExtension,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        if fileExtension == "json", isTiledSceneManifest(asset.path) {
            loadSceneAuthoredPayload(
                url: asset.path,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        if fileExtension == "remotestream",
           let urlString = try? String(contentsOf: asset.path, encoding: .utf8),
           let manifestURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            loadSceneAuthoredPayload(
                url: manifestURL,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        print("⚠️ Scene-authored loading is only supported for .untold assets and tiled scene manifests")
    }
}
