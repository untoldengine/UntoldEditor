//
//  AssetBrowserView+Selection.swift
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
    func promptDeleteAsset() {
        guard let asset = selectedAsset else { return }
        pendingDeleteAsset = asset
        showDeleteConfirmation = true
    }

    // MARK: - Select Asset

    func selectAsset(_ asset: Asset) {
        selectedAsset = asset
        selectedAssetName = asset.name
        updateTargetEntityName(for: selectionManager.selectedEntity)
    }

    func selectedSceneAuthoredAsset() -> Asset? {
        guard let selectedAsset else {
            return nil
        }

        if let runtimeAsset = resolvedRuntimeAsset(for: selectedAsset),
           runtimeAsset.category == AssetCategory.models.rawValue,
           runtimeModelAssetExtensions.contains(runtimeAsset.path.pathExtension.lowercased())
        {
            return runtimeAsset
        }

        if let manifestAsset = resolvedTiledSceneManifest(for: selectedAsset) {
            return manifestAsset
        }

        if selectedAsset.category == AssetCategory.streamModels.rawValue,
           selectedAsset.path.pathExtension.lowercased() == "remotestream"
        {
            return selectedAsset
        }

        return nil
    }

    func loadSelectedSceneAuthoredPayload() {
        guard let asset = selectedSceneAuthoredAsset() else {
            showStatus("Select a .untold model or tiled scene manifest first", isError: true)
            return
        }

        editor_loadSceneAuthoredFromAsset(asset)
        showStatus("Loading authored cameras/lights: \(asset.name)...")
    }

    // MARK: - Delete Asset

    func deleteAsset(_ asset: Asset) {
        guard let basePath = assetBasePath else {
            showBasePathAlert = true
            return
        }

        // Ensure the asset lives under the base path before deleting
        guard asset.path.resolvingSymlinksInPath().path.hasPrefix(basePath.resolvingSymlinksInPath().path) else {
            print("⚠️ Refusing to delete asset outside base path: \(asset.path.path)")
            showStatus("Cannot delete outside Asset Folder", isError: true)
            return
        }

        do {
            try FileManager.default.removeItem(at: asset.path)
            print("✅ Deleted asset: \(asset.name)")
            if selectedAsset?.id == asset.id {
                selectedAsset = nil
                selectedAssetName = nil
            }
            loadAssets()
            // Other listeners (e.g. the Scene Hierarchy's ProjectSceneCatalog) need to
            // know a file disappeared too, not just this view's own asset list.
            NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
            showStatus("Queued delete: \(asset.name) (see Console)")
        } catch {
            print("❌ Failed to delete asset \(asset.name): \(error)")
            showStatus("Delete failed for \(asset.name) (see Console)", isError: true)
        }
    }

    func updateTargetEntityName(for entityId: EntityID?) {
        guard let entityId, entityId != .invalid else {
            targetEntityName = "None"
            return
        }
        let name = getEntityName(entityId: entityId)
        targetEntityName = name.isEmpty ? "Entity \(entityId)" : name
    }
}
