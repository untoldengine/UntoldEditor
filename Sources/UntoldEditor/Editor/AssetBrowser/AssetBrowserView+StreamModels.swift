//
//  AssetBrowserView+StreamModels.swift
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
    func resolvedRuntimeAsset(for asset: Asset) -> Asset? {
        guard asset.isFolder else { return asset }
        guard asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue else {
            return nil
        }
        guard let category = AssetCategory(rawValue: asset.category),
              let runtimeAssetURL = primaryRuntimeAsset(in: asset.path, allowedExtensions: runtimeAssetExtensions(for: category))
        else {
            return nil
        }

        return Asset(
            name: runtimeAssetURL.lastPathComponent,
            category: asset.category,
            path: runtimeAssetURL,
            isFolder: false
        )
    }

    func resolvedTiledSceneManifest(for asset: Asset) -> Asset? {
        guard asset.category == AssetCategory.streamModels.rawValue else {
            return nil
        }

        if asset.isFolder {
            guard let manifestURL = primaryTiledSceneManifest(in: asset.path) else {
                return nil
            }

            return Asset(
                name: manifestURL.lastPathComponent,
                category: asset.category,
                path: manifestURL,
                isFolder: false
            )
        }

        guard isTiledSceneManifest(asset.path) else {
            return nil
        }

        return asset
    }

    func loadStreamModel(from asset: Asset) {
        guard let manifestAsset = resolvedTiledSceneManifest(for: asset) else {
            if asset.isFolder {
                showStatus("No tiled scene manifest found in \(asset.name)", isError: true)
            } else {
                showStatus("Selected JSON is not a tiled scene manifest", isError: true)
            }
            return
        }

        let sceneRoot = createEntity()
        EditorSceneDirtyState.shared.markDirty()
        let sceneName = manifestAsset.path.deletingPathExtension().lastPathComponent
        setEntityName(entityId: sceneRoot, name: sceneName)

        clearSceneBatches()
        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: sceneRoot, url: manifestAsset.path) { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Stream model loaded: \(sceneName)")
                    showStatus("Loaded stream model: \(sceneName)")
                } else {
                    print("⚠️ Failed to load stream model: \(sceneName)")
                    showStatus("Failed to load stream model: \(sceneName)", isError: true)
                }
                sceneGraphModel.refreshHierarchy()
            }
        }

        selectionManager.selectedEntity = sceneRoot
        showStatus("Loading stream model: \(sceneName)...")
    }

    func saveRemoteStream(loadImmediately: Bool) {
        guard let basePath = assetBasePath else {
            showStatus("No project loaded", isError: true)
            return
        }

        let urlStr = remoteStreamURLString.trimmingCharacters(in: .whitespaces)

        guard let remoteURL = URL(string: urlStr),
              remoteURL.scheme?.lowercased() == "https",
              let host = remoteURL.host, !host.isEmpty,
              remoteURL.pathExtension.lowercased() == "json"
        else {
            showStatus("URL must be a valid https:// link ending in .json", isError: true)
            return
        }

        let baseName = remoteURL.deletingPathExtension().lastPathComponent
        // Hash the full URL to avoid collisions between manifests with the same filename on different hosts.
        let urlHash = String(format: "%08x", urlStr.utf8.reduce(UInt32(5381)) { ($0 &* 31) &+ UInt32($1) })
        let name = "\(baseName)-\(urlHash)"

        saveRemoteStreamAsset(
            name: name,
            displayName: baseName,
            urlString: urlStr,
            basePath: basePath,
            loadImmediately: loadImmediately
        )
        remoteStreamURLString = ""
    }

    func saveRemoteStreamAsset(
        name: String,
        displayName: String,
        urlString: String,
        basePath: URL,
        loadImmediately: Bool
    ) {
        let streamModelsFolder = basePath.appendingPathComponent("StreamModels", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: streamModelsFolder, withIntermediateDirectories: true)
            let fileURL = streamModelsFolder
                .appendingPathComponent(name)
                .appendingPathExtension("remotestream")
            try urlString.write(to: fileURL, atomically: true, encoding: .utf8)
            loadAssets()
            let asset = Asset(
                name: displayName,
                category: AssetCategory.streamModels.rawValue,
                path: fileURL,
                isFolder: false
            )
            navigation.lightsSelected = false
            navigation.primitivesSelected = false
            navigation.entitiesSelected = false
            selectedCategory = AssetCategory.streamModels.rawValue
            folderPathStack = []
            if loadImmediately {
                loadRemoteStreamModel(from: asset)
            } else {
                showStatus("Remote stream '\(displayName)' added")
            }
        } catch {
            showStatus("Failed to save remote stream: \(error.localizedDescription)", isError: true)
        }
    }

    func loadRemoteStreamModel(from asset: Asset) {
        guard let urlStr = try? String(contentsOf: asset.path, encoding: .utf8),
              let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            showStatus("Invalid URL in \(asset.name)", isError: true)
            return
        }

        let sceneRoot = createEntity()
        EditorSceneDirtyState.shared.markDirty()
        let sceneName = asset.name
        setEntityName(entityId: sceneRoot, name: sceneName)

        clearSceneBatches()
        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: sceneRoot, url: url) { success in
            DispatchQueue.main.async {
                if success {
                    showStatus("Loaded remote stream: \(sceneName)")
                } else {
                    showStatus("Failed to load remote stream: \(sceneName)", isError: true)
                }
                sceneGraphModel.refreshHierarchy()
            }
        }

        selectionManager.selectedEntity = sceneRoot
        showStatus("Loading remote stream: \(sceneName)...")
    }
}
