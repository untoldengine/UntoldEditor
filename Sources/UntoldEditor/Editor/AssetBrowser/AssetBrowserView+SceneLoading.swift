//
//  AssetBrowserView+SceneLoading.swift
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
    // MARK: - Load Scene Helper

    func loadScene(from url: URL) {
        guard gameMode == false else {
            showBlockedDuringPlayAlert = true
            return
        }
        guard let sceneData = loadGameScene(from: url) else {
            print("❌ Failed to load scene from \(url.lastPathComponent)")
            return
        }

        // Clear current scene
        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()
        EditorGaussianAssetState.shared.clear()
        EditorUndoManager.shared.clear()
        EditorSceneDirtyState.shared.clear()

        // Load new scene
        deserializeScene(sceneData: sceneData, onGaussianEntityRestored: restoreEditorGaussianState)
        NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)

        // Reset editor state
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false

        // Refresh UI
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()

        // Reset camera
        CameraSystem.shared.activeCamera = findSceneCamera()

        editorController?.currentSceneURL = url
        print("✅ Scene loaded: \(url.lastPathComponent)")
    }
}
