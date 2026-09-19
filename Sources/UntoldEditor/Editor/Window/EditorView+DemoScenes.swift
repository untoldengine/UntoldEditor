//
//  EditorView+DemoScenes.swift
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
    // MARK: - Quick Preview

    func editor_loadDemoScene(_ demo: DemoSceneCatalogItem) {
        guard let sourceURL = demo.source.resolvedURL else {
            Logger.log(message: "⚠️ Demo source not found: \(demo.title)")
            showDemoGallery = true
            return
        }

        experienceMode = .explore
        showWelcomeStart = true
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = demo
        activeDemoCameraFrame = demo.cameraFrame
        activePreviewSceneTitle = nil
        activePreviewImportMode = nil
        enableExploreNavigationMode()

        deleteExistingQuickPreviewEntities()
        clearSceneBatches()
        removeGizmo()
        clearExploreSelection()

        switch demo.source {
        case .remoteManifest, .bundledManifest:
            loadDemoStreamScene(demo, manifestURL: sourceURL)
        case .bundledAsset:
            loadDemoRuntimeAsset(demo, assetURL: sourceURL)
        }
    }

    func loadDemoStreamScene(_ demo: DemoSceneCatalogItem, manifestURL: URL) {
        let existingEntityIds = Set(getAllGameEntities())
        let entityId = createDemoPreviewEntity(
            title: demo.title,
            sourceURL: manifestURL,
            fileExtension: "json"
        )

        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: entityId, url: manifestURL) { success in
            DispatchQueue.main.async {
                guard success else {
                    Logger.log(message: "⚠️ Failed to load demo scene: \(demo.title)")
                    showDemoGallery = true
                    return
                }

                loadDemoSceneAuthoredIfNeeded(
                    demo,
                    url: manifestURL,
                    isRuntimeAsset: false,
                    existingEntityIds: existingEntityIds
                ) { didApplyAuthoredCamera in
                    completeDemoSceneLoad(demo, didApplyAuthoredCamera: didApplyAuthoredCamera)
                }
            }
        }
    }

    func loadDemoRuntimeAsset(_ demo: DemoSceneCatalogItem, assetURL: URL) {
        let existingEntityIds = Set(getAllGameEntities())
        let fileExtension = demo.source.fileExtension
        let entityId = createDemoPreviewEntity(
            title: demo.title,
            sourceURL: assetURL,
            fileExtension: fileExtension
        )

        GeometryStreamingSystem.shared.enabled = false

        setEntityMeshAsync(entityId: entityId, filename: assetURL.path, withExtension: fileExtension) { success in
            DispatchQueue.main.async {
                guard success else {
                    Logger.log(message: "⚠️ Failed to load demo asset: \(demo.title)")
                    showDemoGallery = true
                    return
                }

                loadDemoSceneAuthoredIfNeeded(
                    demo,
                    url: assetURL,
                    isRuntimeAsset: true,
                    existingEntityIds: existingEntityIds
                ) { didApplyAuthoredCamera in
                    completeDemoSceneLoad(demo, didApplyAuthoredCamera: didApplyAuthoredCamera)
                }
            }
        }
    }

    func createDemoPreviewEntity(title: String, sourceURL: URL, fileExtension: String) -> EntityID {
        let entityId = createEntity()
        setEntityName(entityId: entityId, name: "Demo-\(title)-\(entityId)")

        registerComponent(entityId: entityId, componentType: QuickPreviewComponent.self)
        if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId) {
            quickPreviewComp.absoluteFilePath = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
            quickPreviewComp.fileExtension = fileExtension
            quickPreviewComp.originalFileName = title
        }

        return entityId
    }

    func loadDemoSceneAuthoredIfNeeded(
        _ demo: DemoSceneCatalogItem,
        url: URL,
        isRuntimeAsset: Bool,
        existingEntityIds: Set<EntityID>,
        completion: @escaping (Bool) -> Void
    ) {
        guard demo.loadsSceneAuthoredPayload else {
            completion(false)
            return
        }

        if isRuntimeAsset {
            loadSceneAuthored(filename: url.path, withExtension: url.pathExtension.lowercased()) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        } else {
            loadSceneAuthored(url: url) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        }
    }

    func completeDemoSceneLoad(_ demo: DemoSceneCatalogItem, didApplyAuthoredCamera: Bool) {
        if didApplyAuthoredCamera == false, let frame = demo.cameraFrame {
            applyCameraFrame(frame)
        }

        clearExploreSelection()
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        enableExploreNavigationMode()
        revealCameraControlHintsIfNeeded()

        Logger.log(message: "✅ Demo loaded: \(demo.title)")
    }

    func clearExploreSelection() {
        removeGizmo()
        activeEntity = .invalid
        gizmoActive = false
        selectionManager.selectedEntity = nil
        selectionManager.inspectedMesh = nil
        selectionManager.objectWillChange.send()
    }
}
