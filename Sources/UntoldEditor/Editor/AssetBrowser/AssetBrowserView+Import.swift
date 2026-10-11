//
//  AssetBrowserView+Import.swift
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

/// Source extensions a Gaussian capture comes in -- kept apart from `sourceAssetExtensions`
/// (which is specifically USD/.blend, see `AssetFileHelpers.swift`) since the two dispatch
/// to different importers (`importGaussianAsset` vs. `importSourceAsset`).
let gaussianSourceAssetExtensions: Set<String> = ["ply", "spz"]

/// Extensions the toolbar's generic Import button also recognizes beyond a raw source:
/// an already-cooked runtime asset, routed straight into the GameData category its
/// extension names (see `importAssetAutoRouted`) instead of staged in Resources -- there's
/// nothing left to cook. Unambiguous by extension with current releases: an old project's
/// animation still saved as a bare ".untold" (from before ".untoldanim" existed) lands in
/// Models here, same as a model would; GameData/Animations' own Import still accepts it
/// correctly.
let cookedAssetCategoryByExtension: [String: AssetCategory] = [
    runtimeAssetExtension: .models,
    "untoldpack": .models,
    "untoldanim": .animations,
    "untoldgs": .gaussians,
    untoldSceneFileExtension: .scenes,
    "uscript": .scripts,
]

extension AssetBrowserView {
    /// Queues the copy of one raw source (`.blend`/USD or `.ply`/`.spz`) into
    /// `destinationFolder` (always somewhere under Resources). Shared by
    /// `importSourcesIntoResources` (Finder-style, wherever in Resources the user is
    /// browsing) and `importAssetAutoRouted` (always the Resources root).
    func enqueueResourcesImport(sourceURL: URL, into destinationFolder: URL, batch: DispatchGroup, fileManager fm: FileManager) {
        let sourceExtension = sourceURL.pathExtension.lowercased()
        if gaussianSourceAssetExtensions.contains(sourceExtension) {
            let destFolder = gaussianPackageFolder(for: sourceURL, in: destinationFolder)
            enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                _ = try importGaussianAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                    try ctx.copy($0, to: $1, fileManager: fm)
                }
            }
        } else if sourceAssetExtensions.contains(sourceExtension) {
            let baseName = sourceURL.deletingPathExtension().lastPathComponent
            let destFolder = destinationFolder.appendingPathComponent(baseName, isDirectory: true)
            enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                _ = try importSourceAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                    try ctx.copy($0, to: $1, fileManager: fm)
                }
            }
        }
    }

    /// Shows the post-import "right-click to cook" hint after a single raw source lands
    /// in Resources (see `BakePromptSheet`) -- skipped for a multi-file import (a choice
    /// per file isn't worth a sheet) and for an already-cooked file (nothing to cook).
    func maybeShowBakePrompt(for importedURLs: [URL]) {
        guard !hideBakePromptAfterImport, importedURLs.count == 1, let sourceURL = importedURLs.first else { return }
        let sourceExtension = sourceURL.pathExtension.lowercased()
        guard gaussianSourceAssetExtensions.contains(sourceExtension) || sourceAssetExtensions.contains(sourceExtension) else { return }
        pendingBakePrompt = BakePromptRequest(sourceURL: sourceURL)
    }

    func importIntoCurrentDirectory() {
        // Resources/ is free-form -- there's no single category to restrict the file
        // picker to (which category a source becomes is decided at cook time, not
        // import time, see the context menu in AssetBrowserView+Contents.swift), so
        // every recognized source type is offered at once instead of defaulting to one.
        if let current = currentDirectoryURL, let basePath = assetBasePath, isUnderResources(current, assetBasePath: basePath) {
            importSourcesIntoResources(at: current)
            return
        }
        let category = selectedCategory.flatMap { AssetCategory(rawValue: $0) }
            ?? inferCategory(for: currentDirectoryURL)
            ?? .models
        importAssetForCategory(category, into: currentDirectoryURL)
    }

    /// Import entry point used while browsing anywhere under `Resources/`: the open
    /// panel allows every recognized source extension at once, and each selected file
    /// is dispatched to the importer its own extension calls for -- a `.ply`/`.spz`
    /// through `importGaussianAsset`, a `.blend`/USD through `importSourceAsset` --
    /// landing in its own folder directly in `destinationFolder` (Finder-style,
    /// wherever in `Resources/` the user is).
    func importSourcesIntoResources(at destinationFolder: URL) {
        guard editorBaseAssetPath.basePath != nil else {
            showBasePathAlert = true
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = sourceAssetExtensions.union(gaussianSourceAssetExtensions).sorted().compactMap {
            UTType(filenameExtension: $0)
        }
        openPanel.allowsMultipleSelection = true

        let fm = FileManager.default
        try? fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        guard openPanel.runModal() == .OK else { return }

        let batch = DispatchGroup()
        for sourceURL in openPanel.urls {
            enqueueResourcesImport(sourceURL: sourceURL, into: destinationFolder, batch: batch, fileManager: fm)
        }

        let count = openPanel.urls.count
        showStatus("Importing \(count) item(s) (see Tasks)...")

        batch.notify(queue: .main) {
            loadAssets()
            if runtimeExportQueue.isEmpty, pendingRuntimeExport == nil,
               tilesExportQueue.isEmpty, pendingTilesExport == nil
            {
                showStatus("Imported \(count) item(s)")
            }
            // Only for a single-file import: a batch would need the same choice made
            // once per file, which isn't worth a modal, so it's left to the right-click
            // menu instead.
            maybeShowBakePrompt(for: openPanel.urls)
        }
    }

    /// The toolbar's always-available "Import…": picks a destination by the file's own
    /// extension rather than wherever the user happens to be browsing. A raw source
    /// (`.blend`, USD, `.ply`/`.spz`) stages into the Resources root, free-form, same as
    /// `importSourcesIntoResources`; an already-cooked file
    /// (`cookedAssetCategoryByExtension`) goes straight into its GameData category,
    /// since there's nothing left to cook.
    func importAssetAutoRouted() {
        guard editorBaseAssetPath.basePath != nil else {
            showBasePathAlert = true
            return
        }
        guard let resourcesRoot = resourcesRootURL else {
            importIntoCurrentDirectory()
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = sourceAssetExtensions
            .union(gaussianSourceAssetExtensions)
            .union(cookedAssetCategoryByExtension.keys)
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }
        openPanel.allowsMultipleSelection = true

        let fm = FileManager.default
        try? fm.createDirectory(at: resourcesRoot, withIntermediateDirectories: true)

        guard openPanel.runModal() == .OK else { return }

        let batch = DispatchGroup()
        for sourceURL in openPanel.urls {
            let sourceExtension = sourceURL.pathExtension.lowercased()

            guard let category = cookedAssetCategoryByExtension[sourceExtension] else {
                enqueueResourcesImport(sourceURL: sourceURL, into: resourcesRoot, batch: batch, fileManager: fm)
                continue
            }
            guard let categoryRoot = categoryRootURL(category) else { continue }
            try? fm.createDirectory(at: categoryRoot, withIntermediateDirectories: true)

            switch category {
            case .gaussians:
                let destFolder = gaussianPackageFolder(for: sourceURL, in: categoryRoot)
                enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                    _ = try importGaussianAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                        try ctx.copy($0, to: $1, fileManager: fm)
                    }
                }
            case .scenes, .scripts:
                let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                enqueueImport(destination: destURL, isFolder: false, batch: batch) { ctx in
                    try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                }
            default:
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                    try importRuntimeAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                        try ctx.copy($0, to: $1, fileManager: fm)
                    }
                }
            }
        }

        let count = openPanel.urls.count
        showStatus("Importing \(count) item(s) (see Tasks)...")

        batch.notify(queue: .main) {
            loadAssets()
            if runtimeExportQueue.isEmpty, pendingRuntimeExport == nil,
               tilesExportQueue.isEmpty, pendingTilesExport == nil
            {
                showStatus("Imported \(count) item(s)")
            }
            maybeShowBakePrompt(for: openPanel.urls)
        }
    }

    func importAssetForCategory(_ category: AssetCategory, into destinationOverride: URL? = nil) {
        guard editorBaseAssetPath.basePath != nil else {
            showBasePathAlert = true
            return
        }

        let openPanel = NSOpenPanel()

        // Set allowed file types based on category
        switch category {
        case .models:
            openPanel.allowedContentTypes = (runtimeModelAssetExtensions.sorted() + sourceAssetExtensions.sorted()).compactMap {
                UTType(filenameExtension: $0)
            }
        case .animations:
            openPanel.allowedContentTypes = (runtimeAnimationAssetExtensions.sorted() + sourceAssetExtensions.sorted()).compactMap {
                UTType(filenameExtension: $0)
            }
        case .streamModels:
            openPanel.allowedContentTypes = ([UTType(filenameExtension: "json")!] + sourceAssetExtensions.sorted().compactMap { UTType(filenameExtension: $0) })
        case .scripts:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "uscript")!]
        case .scenes:
            openPanel.allowedContentTypes = [.untoldScene]
        case .gaussians:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "ply")!, UTType(filenameExtension: "spz")!, UTType(filenameExtension: "untoldgs")!]
        case .materials:
            openPanel.allowedContentTypes = [.png, .jpeg, .tiff]
        case .hdr:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "hdr")!, UTType(filenameExtension: "exr")!]
        case .lut:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        }

        openPanel.canChooseDirectories = (category == .materials || category == .streamModels || category == .gaussians)
        openPanel.allowsMultipleSelection = true

        guard let basePath = assetBasePath else { return }
        let categoryString = category.rawValue
        // Ensure category is valid
        guard AssetCategory.allCases.map(\.rawValue).contains(categoryString) else { return }

        let fm = FileManager.default
        // Import into the folder the user has open (Finder-style), falling back
        // to the category root.
        let categoryRoot = destinationOverride ?? basePath.appendingPathComponent(categoryString, isDirectory: true)
        // Ensure the destination folder exists (e.g., <Base>/Models or a subfolder)
        try? fm.createDirectory(at: categoryRoot, withIntermediateDirectories: true)

        guard openPanel.runModal() == .OK else { return }

        // Every copy is its own Tasks-panel job on the import queue; the batch group
        // fires once they have all landed (or failed).
        let batch = DispatchGroup()

        for sourceURL in openPanel.urls {
            switch categoryString {
            case "HDR", "LUT", "Scenes", "Scripts":
                // Plain copy into the folder
                let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                enqueueImport(destination: destURL, isFolder: false, batch: batch) { ctx in
                    try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                }

            case "Gaussians":
                if sourceURL.hasDirectoryPath {
                    guard primaryGaussianAsset(in: sourceURL, fileManager: fm) != nil else {
                        showStatus("No Gaussian asset found in selected folder", isError: true)
                        continue
                    }

                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    // A raw .ply/.spz is a source, same as a .blend: it goes into
                    // Resources/, free-form (no Gaussians/ segment, same as any other
                    // source -- see cookGaussianSources for where the cook's output
                    // lands). An already-cooked .untoldgs stays in GameData, same as a
                    // runtime .untold/.untoldpack would.
                    let sourceExtension = sourceURL.pathExtension.lowercased()
                    let baseName = gaussianPackageName(for: sourceURL)
                    let importFolder = ["ply", "spz"].contains(sourceExtension)
                        ? (resourcesImportFolder(forBaseName: baseName, browsing: destinationOverride, assetBasePath: basePath)
                            ?? gaussianPackageFolder(for: sourceURL, in: categoryRoot))
                        : gaussianPackageFolder(for: sourceURL, in: categoryRoot)
                    enqueueImport(destination: importFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importGaussianAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                }

            case "Materials":
                if sourceURL.hasDirectoryPath {
                    // Copy entire material folder (recommended)
                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    // Single texture fallback → folder named after the file (without ext)
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let materialFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    enqueueImport(destination: materialFolder, isFolder: true, batch: batch) { ctx in
                        try fm.createDirectory(at: ctx.stagingURL, withIntermediateDirectories: true)
                        try ctx.copy(sourceURL, to: ctx.stagingURL.appendingPathComponent(sourceURL.lastPathComponent), fileManager: fm)
                    }
                }

            case "Models", "Animations":
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                let sourceExtension = sourceURL.pathExtension.lowercased()

                if runtimeAssetExtensions(for: category).contains(sourceExtension) {
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        try importRuntimeAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                } else if sourceAssetExtensions.contains(sourceExtension) {
                    // Import = copy the source into the project, into Resources/,
                    // free-form (no Models/Animations/... segment -- which category it
                    // becomes is decided at cook time, not import time, see the context
                    // menu in AssetBrowserView+Contents.swift). Falls back to GameData
                    // on the legacy layout, which has no Resources/ to redirect into.
                    let importFolder = resourcesImportFolder(forBaseName: baseName, browsing: destinationOverride, assetBasePath: basePath)
                        ?? destFolder
                    enqueueImport(destination: importFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importSourceAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                }

            case "StreamModels":
                let sourceExtension = sourceURL.pathExtension.lowercased()
                if sourceAssetExtensions.contains(sourceExtension) {
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    // Same as Models: keep the source in Resources/, free-form. Tiling
                    // happens when the user asks for it, from the row's "Cook to tiled
                    // stream model…" context action.
                    let importFolder = resourcesImportFolder(forBaseName: baseName, browsing: destinationOverride, assetBasePath: basePath)
                        ?? destFolder
                    enqueueImport(destination: importFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importSourceAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                } else if sourceURL.hasDirectoryPath {
                    guard primaryTiledSceneManifest(in: sourceURL, fileManager: fm) != nil else {
                        showStatus("No tiled scene manifest found in selected folder", isError: true)
                        continue
                    }

                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else if isTiledSceneManifest(sourceURL) {
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        try fm.createDirectory(at: ctx.stagingURL, withIntermediateDirectories: true)
                        try importStreamModelManifest(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    showStatus("Selected JSON is not a tiled scene manifest", isError: true)
                }

            default:
                break
            }
        }

        let count = openPanel.urls.count
        showStatus("Importing \(count) item(s) (see Tasks)...")

        batch.notify(queue: .main) {
            loadAssets()
            if runtimeExportQueue.isEmpty, pendingRuntimeExport == nil,
               tilesExportQueue.isEmpty, pendingTilesExport == nil
            {
                showStatus("Imported \(count) item(s)")
            }
        }
    }

    /// Copies one imported item as a Tasks-panel job (see `importAssetTracked`). The
    /// item is hidden until the copy is complete; if the copy is still running after
    /// `assetImportPlaceholderDelay` the content panel shows a placeholder row for it
    /// with the copy progress. `completion` runs on the main queue with the final URL
    /// only when the copy worked.
    func enqueueImport(
        destination: URL,
        isFolder: Bool,
        batch: DispatchGroup,
        work: @escaping (AssetImportContext) throws -> Void,
        completion: @escaping (URL) -> Void = { _ in }
    ) {
        let pending = PendingAssetImport(destinationURL: destination, isFolder: isFolder)
        pendingImports.append(pending)
        batch.enter()

        DispatchQueue.main.asyncAfter(deadline: .now() + assetImportPlaceholderDelay) {
            guard let index = pendingImports.firstIndex(where: { $0.id == pending.id }) else { return }
            pendingImports[index].showsPlaceholder = true
        }

        let detail = assetBasePath.map { base in
            destination.deletingLastPathComponent().path
                .replacingOccurrences(of: base.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } ?? ""
        importAssetTracked(
            destination: destination,
            detail: detail.isEmpty ? "" : "→ \(detail)/",
            onProgress: { progress in
                guard let index = pendingImports.firstIndex(where: { $0.id == pending.id }) else { return }
                pendingImports[index].progress = progress
            },
            work: work
        ) { result in
            pendingImports.removeAll { $0.id == pending.id }
            switch result {
            case let .success(url):
                loadAssets()
                completion(url)
            case .failure(is CancellationError):
                showStatus("Import cancelled: \(destination.lastPathComponent)")
            case let .failure(error):
                showStatus("Import failed for \(destination.lastPathComponent): \(error.localizedDescription)", isError: true)
                Logger.log(message: "❌ Import failed for \(destination.lastPathComponent): \(error)")
            }
            batch.leave()
        }
    }

    func importRuntimeAsset(
        sourceURL: URL,
        destinationFolder: URL,
        fileManager fm: FileManager,
        copy: ((URL, URL) throws -> Void)? = nil
    ) throws {
        let copyFile = copy ?? { try fm.copyItem(at: $0, to: $1) }
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let destinationAsset = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destinationAsset.path) {
            try fm.removeItem(at: destinationAsset)
        }
        try copyFile(sourceURL, destinationAsset)
        try copyRuntimeAssetSidecars(for: sourceURL, to: destinationFolder, fileManager: fm)
        try copyUntoldPackResources(for: sourceURL, to: destinationFolder, fileManager: fm)
    }
}
