//
//  AssetBrowserView+Placement.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

extension AssetBrowserView {
    // MARK: - Add Model with Double Click

    func selectedMaterialTarget() -> (entityId: EntityID, meshIndex: Int)? {
        if let inspectedMesh = selectionManager.inspectedMesh,
           inspectedMesh.entityId != .invalid,
           hasComponent(entityId: inspectedMesh.entityId, componentType: RenderComponent.self)
        {
            return (inspectedMesh.entityId, inspectedMesh.meshIndex)
        }

        guard let entityId = selectionManager.selectedEntity,
              entityId != .invalid,
              hasComponent(entityId: entityId, componentType: RenderComponent.self)
        else {
            return nil
        }

        return (entityId, 0)
    }

    func assignMaterialFolder(_ asset: Asset) {
        guard asset.category == AssetCategory.materials.rawValue, asset.isFolder else {
            return
        }

        guard let target = selectedMaterialTarget() else {
            showStatus("Select a mesh before assigning materials", isError: true)
            return
        }

        let assignments = editorMaterialTextureAssignments(in: asset.path)
        guard assignments.isEmpty == false else {
            showStatus("No recognized material textures in \(asset.name)", isError: true)
            return
        }

        for textureType in TextureType.allCases {
            guard let textureURL = assignments[textureType] else { continue }
            updateMaterialTexture(
                entityId: target.entityId,
                textureType: textureType,
                path: textureURL,
                meshIndex: target.meshIndex
            )
        }

        selectionManager.objectWillChange.send()
        showStatus("Assigned \(assignments.count) material textures from \(asset.name)")
    }

    func handle_add_model_double_click(asset: Asset) {
        if asset.category == AssetCategory.materials.rawValue, asset.isFolder {
            assignMaterialFolder(asset)
            return
        }

        if asset.category == AssetCategory.streamModels.rawValue {
            if asset.path.pathExtension.lowercased() == "remotestream" {
                loadRemoteStreamModel(from: asset)
            } else {
                loadStreamModel(from: asset)
            }
            return
        }

        // Models (.untold, .untoldpack, or a folder's primary) and Gaussian splats (.ply,
        // baked .untoldgs, or an imported package folder) take the same path as a
        // drag-and-drop onto the scene.
        if let placeable = placeableAsset(for: asset) {
            let placement = placeAsset(placeable, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
            return
        }
        if asset.isFolder, asset.category == AssetCategory.gaussians.rawValue {
            showStatus(unsupportedAssetDropMessage(for: asset), isError: true)
            return
        }

        guard let asset = resolvedRuntimeAsset(for: asset) else {
            if asset.isFolder,
               asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue
            {
                showStatus("No primary runtime asset found in \(asset.name)", isError: true)
            }
            return
        }

        let filename = asset.path.deletingPathExtension().lastPathComponent
        let runtimeFilename = runtimeAssetFilenameForLoading(asset.path)
        let withExtension = asset.path.pathExtension

        // Handle Animation files (.untold runtime assets in Animations category)
        if asset.category == AssetCategory.animations.rawValue,
           runtimeAnimationAssetExtensions.contains(withExtension.lowercased())
        {
            // Animations require a selected entity to work with
            guard let entityId = selectionManager.selectedEntity,
                  entityId != .invalid
            else {
                print("⚠️ Please select an entity first to add animation")
                showStatus("Select an entity before adding animation", isError: true)
                return
            }

            guard canAuthorAnimationComponent(entityId: entityId) else {
                print("⚠️ Select a mesh node to add animation")
                showStatus("Select a mesh node before adding animation", isError: true)
                return
            }

            // Add the animation to the entity
            setEntityAnimations(entityId: entityId, filename: runtimeFilename, withExtension: withExtension, name: filename)

            // Store the animation file URL in the component
            for targetEntityId in editorAnimationBindingTargetEntities(for: entityId) {
                guard let animationComponent = scene.get(component: AnimationComponent.self, for: targetEntityId) else {
                    continue
                }

                if animationComponent.animationsFilenames.contains(asset.path) == false {
                    animationComponent.animationsFilenames.append(asset.path)
                }
            }

            // Refresh view
            selectionManager.objectWillChange.send()
            showStatus("Queued animation link to \(targetEntityName) (see Console)")
        }
        // Handle Script files (uscript)
        else if asset.category == AssetCategory.scripts.rawValue,
                withExtension.lowercased() == "uscript"
        {
            guard EditorAuthoringMode.sceneCompositionOnly == false else {
                showStatus("Scripts are linked in code for scene-composition projects", isError: true)
                return
            }

            // Scripts require a selected entity to work with
            guard let entityId = selectionManager.selectedEntity,
                  entityId != .invalid
            else {
                print("⚠️ Please select an entity first to add script")
                showStatus("Select an entity before adding script", isError: true)
                return
            }

            // Get or create ScriptComponent
            let scriptComponent: ScriptComponent
            if let existing = scene.get(component: ScriptComponent.self, for: entityId) {
                scriptComponent = existing
            } else {
                guard let newComp = scene.assign(to: entityId, component: ScriptComponent.self) else {
                    print("❌ Failed to create ScriptComponent")
                    return
                }
                scriptComponent = newComp
            }

            // Load and append the script
            do {
                let jsonData = try Data(contentsOf: asset.path)
                let decoder = JSONDecoder()
                let loadedScript = try decoder.decode(USCScript.self, from: jsonData)

                // Append script and its path
                scriptComponent.scripts.append(loadedScript)
                if scriptComponent.scriptFilePaths == nil {
                    scriptComponent.scriptFilePaths = []
                }
                scriptComponent.scriptFilePaths?.append(asset.path.path)

                print("✅ Script added: \(loadedScript.name)")

                // Refresh view
                selectionManager.objectWillChange.send()
                showStatus("Queued script link to \(targetEntityName) (see Console)")
            } catch {
                print("❌ Failed to load script: \(error.localizedDescription)")
            }
        }
        // Handle Scene files (.untoldscene)
        else if asset.category == AssetCategory.scenes.rawValue,
                withExtension.lowercased() == untoldSceneFileExtension
        {
            guard gameMode == false else {
                showBlockedDuringPlayAlert = true
                return
            }
            requestDestructiveSceneAction(
                { loadScene(from: asset.path) },
                describing: "loading a new scene",
                showAlert: $showUnsavedChangesAlert,
                alertMessage: $unsavedChangesAlertMessage
            )
        }
        // Handle HDR files (hdr, exr)
        else if asset.category == AssetCategory.hdr.rawValue,
                ["hdr", "exr"].contains(withExtension.lowercased())
        {
            // Verify HDR file exists before attempting to load
            guard FileManager.default.fileExists(atPath: asset.path.path) else {
                Logger.log(message: "⚠️ HDR file not found: \(asset.path.path)")
                showStatus("HDR file not found", isError: true)
                return
            }

            // Load HDR as environment IBL
            let filename = asset.path.lastPathComponent
            let directoryURL = asset.path.deletingLastPathComponent()
            generateHDR(filename, from: directoryURL)

            // Only enable IBL if HDR was successfully loaded
            if iblSuccessful {
                applyIBL = true
                print("✅ HDR environment loaded and IBL enabled: \(filename)")
                showStatus("HDR loaded and IBL enabled: \(filename)")
            } else {
                print("⚠️ Failed to load HDR: \(filename)")
                showStatus("Failed to load HDR: \(filename)", isError: true)
            }
        }
    }
}
