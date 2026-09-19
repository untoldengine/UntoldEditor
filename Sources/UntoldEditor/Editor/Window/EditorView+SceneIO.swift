//
//  EditorView+SceneIO.swift
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
    var saveScenePrompt: some View {
        VStack(spacing: 12) {
            Text("Save Scene")
                .font(.headline)
            Text("Scenes are saved to the Scenes folder in your Asset Folder.")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)

            TextField("Scene name", text: $pendingSceneName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { confirmSaveSceneName() }

            HStack {
                Button("Cancel") {
                    showSaveNamePrompt = false
                    EditorPendingSwitchAction.shared.cancel()
                }
                Spacer()
                Button("Save") { confirmSaveSceneName() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingSceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }

    func editor_handleSave() {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        guard assetBasePath != nil else {
            showSaveBasePathAlert = true
            return
        }

        // Ensure Save always means Save, even after a stale/cancelled Save-As
        // attempt left this flag set (deleteQuickPreviewEntitiesAndSave() routes
        // on it, and nothing else resets it before now).
        isSaveAs = false

        // Check for Quick Preview entities before saving
        if checkForQuickPreviewEntities() {
            return
        }

        // If we have a current scene path, save immediately
        if let sceneURL = editorController?.currentSceneURL {
            let sceneData: SceneData = serializeScene()
            do {
                try saveSceneDirect(sceneData: sceneData, to: sceneURL)
                sceneCatalog.refresh()
                EditorSceneDirtyState.shared.markSaved()
                EditorPendingSwitchAction.shared.consume()
            } catch {
                saveFailedMessage = "\(error)"
                showSaveFailedAlert = true
            }
            return
        }

        // Otherwise prompt for a name
        isSaveAs = false
        pendingSceneName = "untitled"
        showSaveNamePrompt = true
    }

    func editor_handleSaveAs() {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        guard assetBasePath != nil else {
            showSaveBasePathAlert = true
            return
        }

        // Check for Quick Preview entities before saving
        if checkForQuickPreviewEntities() {
            return
        }

        isSaveAs = true
        if let current = editorController?.currentSceneURL {
            pendingSceneName = current.deletingPathExtension().lastPathComponent
        } else {
            pendingSceneName = "untitled"
        }
        showSaveNamePrompt = true
    }

    func confirmSaveSceneName() {
        let name = pendingSceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        guard let basePath = assetBasePath else {
            showSaveNamePrompt = false
            print("❌ Cannot save scene: Asset Folder not set.")
            return
        }

        let scenesFolder = basePath.appendingPathComponent("Scenes", isDirectory: true)
        try? FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        let targetURL = scenesFolder.appendingPathComponent(name).appendingPathExtension(untoldSceneFileExtension)
        pendingTargetURL = targetURL

        if FileManager.default.fileExists(atPath: targetURL.path) {
            showOverwriteAlert = true
            return
        }

        finalizeSceneSave(targetURL: targetURL, overwrite: false)
    }

    func finalizeSceneSave(targetURL: URL? = nil, overwrite: Bool = false) {
        let sceneData: SceneData = serializeScene()

        let destinationURL: URL
        if let targetURL {
            destinationURL = targetURL
        } else if let existing = editorController?.currentSceneURL {
            destinationURL = existing
        } else {
            showSaveNamePrompt = true
            return
        }

        if FileManager.default.fileExists(atPath: destinationURL.path), !overwrite {
            showOverwriteAlert = true
            return
        }

        do {
            try saveSceneDirect(sceneData: sceneData, to: destinationURL)
            editorController?.currentSceneURL = destinationURL
            showSaveNamePrompt = false
            showOverwriteAlert = false
            isSaveAs = false
            sceneCatalog.refresh()
            EditorSceneDirtyState.shared.markSaved()
            EditorPendingSwitchAction.shared.consume()
        } catch {
            saveFailedMessage = "\(error)"
            showSaveFailedAlert = true
        }
    }

    func editor_handleLoad() {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        var sceneData: SceneData?

        // Check if a scene is selected in the Asset Browser
        if let asset = selectedAsset,
           asset.category == "Scenes",
           asset.path.pathExtension.lowercased() == untoldSceneFileExtension
        {
            // Load from selected asset
            sceneData = loadGameScene(from: asset.path)
        } else {
            // Fall back to file picker
            sceneData = loadGameScene()
        }

        if let sceneData {
            destroyAllEntities()
            removeGizmo()
            EditorComponentsState.shared.clear()
            EditorGaussianAssetState.shared.clear()
            EditorUndoManager.shared.clear()
            EditorMenuPluginHost.shared.sceneDidReset()
            EditorSceneDirtyState.shared.clear()
            sceneAuthoredGameCamera = nil
            deserializeScene(sceneData: sceneData, onGaussianEntityRestored: restoreEditorGaussianState)
            NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
            editorController?.currentSceneURL = nil
            editor_entities = getAllGameEntities()
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            gizmoActive = false
            selectionManager.objectWillChange.send()
            sceneGraphModel.refreshHierarchy()

            CameraSystem.shared.activeCamera = findSceneCamera()
        }
    }

    /// Load a scene file from the project into the (single) ECS world, replacing
    /// whatever is currently loaded. Used by the Scene Graph panel.
    func editor_loadScene(from url: URL) {
        guard let sceneData = loadGameScene(from: url) else {
            print("❌ Failed to load scene from \(url.lastPathComponent)")
            return
        }

        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()
        EditorGaussianAssetState.shared.clear()
        EditorUndoManager.shared.clear()
        EditorMenuPluginHost.shared.sceneDidReset()
        EditorSceneDirtyState.shared.clear()
        sceneAuthoredGameCamera = nil

        deserializeScene(sceneData: sceneData, onGaussianEntityRestored: restoreEditorGaussianState)
        NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
        editorController?.currentSceneURL = url

        editor_entities = getAllGameEntities()
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()
        sceneCatalog.refresh()

        CameraSystem.shared.activeCamera = findSceneCamera()
        print("✅ Scene loaded: \(url.lastPathComponent)")
    }

    /// Ask before switching scenes: loading discards the current world.
    func editor_requestLoadScene(_ url: URL) {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        if url == editorController?.currentSceneURL {
            return
        }
        requestDestructiveSceneAction(
            { editor_loadScene(from: url) },
            describing: "loading a new scene",
            showAlert: $showUnsavedChangesAlert,
            alertMessage: $unsavedChangesAlertMessage
        )
    }

    /// Save the project. Projects persist as folders (scenes + imported assets on
    /// disk), so for now this writes the active scene's work into the project.
    func editor_saveProject() {
        editor_handleSave()
    }

    /// Start a fresh scene (File → Add New Scene) and immediately write it to disk
    /// as a uniquely-named `.untoldscene` file, so it behaves like any other scene
    /// from the start (savable in place, visible in the tree) instead of staying
    /// path-less until the user later does Save As.
    func editor_newScene() {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        guard let basePath = assetBasePath else {
            showSaveBasePathAlert = true
            return
        }

        let scenesFolder = basePath.appendingPathComponent("Scenes", isDirectory: true)
        try? FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)
        let destinationURL = uniqueNewSceneURL(in: scenesFolder)

        editor_clearScene()

        let sceneData: SceneData = serializeScene()
        do {
            try saveSceneDirect(sceneData: sceneData, to: destinationURL)
            editorController?.currentSceneURL = destinationURL
            sceneCatalog.refresh()
            selectionManager.selectScene()
            EditorSceneDirtyState.shared.markSaved()
        } catch {
            print("❌ Failed to create new scene file at \(destinationURL.lastPathComponent): \(error)")
            editorController?.currentSceneURL = nil
            selectionManager.selectScene()
        }
    }

    /// Picks a collision-free `.untoldscene` URL inside `folder`: "New Scene",
    /// then "New Scene 2", "New Scene 3", ... — same auto-increment idiom as
    /// `createFolder(in:)` in AssetBrowserView.swift.
    func uniqueNewSceneURL(in folder: URL) -> URL {
        let fm = FileManager.default
        var name = "New Scene"
        var index = 1
        var candidate = folder.appendingPathComponent(name).appendingPathExtension(untoldSceneFileExtension)
        while fm.fileExists(atPath: candidate.path) {
            index += 1
            name = "New Scene \(index)"
            candidate = folder.appendingPathComponent(name).appendingPathExtension(untoldSceneFileExtension)
        }
        return candidate
    }

    func editor_clearScene() {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()
        EditorGaussianAssetState.shared.clear()
        EditorUndoManager.shared.clear()
        EditorMenuPluginHost.shared.sceneDidReset()
        sceneAuthoredGameCamera = nil

        let light = createEntity()
        setEntityName(entityId: light, name: "Directional Light")
        createDirLight(entityId: light)
        // destroyAllEntities() above only marks the previous scene's entities for deferred
        // destruction; the actual cleanup (which nulls activeDirectionalLight if it pointed
        // at the old light) doesn't run until finalizePendingDestroys() later this frame.
        // createDirLight()'s "activate only if nil" check can therefore see a stale non-nil
        // pointer here and skip activating this new light. Force it active explicitly so a
        // freshly cleared scene never ends up with an inactive (shadow-less) default sun.
        setDirectionalLight(.active(light))

        let sceneCamera = findSceneCamera()

        resetCameraToDefaultTransform(entityId: sceneCamera)

        let gameCamera = findGameCamera()

        resetCameraToDefaultTransform(entityId: gameCamera)

        // Environment/post-FX are process-wide globals, not tied to any single
        // entity destroyAllEntities() destroys — reset them explicitly so a
        // freshly cleared scene doesn't inherit whatever the previous scene had.
        applyIBL = false
        renderEnvironment = false
        renderSkyBackground = false
        ambientIntensity = 0.4
        antiAliasingMode = .fxaa
        TonemapParams.shared.resetToDefaults()
        ColorGradingParams.shared.resetToDefaults()
        BloomThresholdParams.shared.resetToDefaults()
        VignetteParams.shared.resetToDefaults()
        ChromaticAberrationParams.shared.resetToDefaults()
        DepthOfFieldParams.shared.resetToDefaults()
        SSAOParams.shared.resetToDefaults()
        FXAAParams.shared.resetToDefaults()
        SMAAParams.shared.resetToDefaults()
        NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)

        editor_entities = getAllGameEntities()
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()

        CameraSystem.shared.activeCamera = sceneCamera
        // Doesn't touch currentSceneURL, so a bare "Reset Scene" leaves this default
        // content disagreeing with whatever's saved at the old URL. editor_newScene()
        // overrides this back to clear() once its own save succeeds.
        EditorSceneDirtyState.shared.markDirty()
    }

    func editor_cameraSave() {
        let sceneCameraEntityID = findSceneCamera()

        if sceneCameraEntityID == .invalid {
            return
        }

        let gameCameraEntityID = findEditorGameCamera()

        if gameCameraEntityID == .invalid {
            return
        }

        let eye = getCameraEye(entityId: sceneCameraEntityID)
        let up = getCameraUp(entityId: sceneCameraEntityID)
        let target = getCameraTarget(entityId: sceneCameraEntityID)

        cameraLookAt(entityId: gameCameraEntityID, eye: eye, target: target, up: up)
    }

    func editor_loadUSDScene() { /*
     guard let url = openFilePicker() else { return }

     let filename = url.deletingPathExtension().lastPathComponent
     let withExtension = url.pathExtension

     loadScene(filename: filename, withExtension: withExtension)
     editor_entities = getAllGameEntities()
     selectionManager.selectedEntity = nil
     activeEntity = .invalid
     selectionManager.objectWillChange.send()

     CameraSystem.shared.activeCamera = findSceneCamera()
                                      */
    }
}
