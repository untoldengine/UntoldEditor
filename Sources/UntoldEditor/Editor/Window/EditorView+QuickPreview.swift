//
//  EditorView+QuickPreview.swift
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
    func editor_handleQuickPreview(mode: QuickPreviewImportMode, fromExploreMode: Bool = false) {
        let openPanel = NSOpenPanel()
        openPanel.title = mode.filePickerTitle
        openPanel.allowedContentTypes = mode.allowedContentTypes
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.message = mode.filePickerMessage

        guard openPanel.runModal() == .OK, let fileURL = openPanel.url else {
            if fromExploreMode {
                showPreviewImportGallery = true
            }
            return
        }

        let fileExtension = fileURL.pathExtension.lowercased()
        let absolutePath = fileURL.path
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        pendingQuickPreviewLoadsInExplore = fromExploreMode

        if isConvertibleSourceAsset(fileURL) {
            queueQuickPreviewRuntimeExport(sourceURL: fileURL)
            return
        }

        if fileExtension == "json", !isTiledSceneManifest(fileURL) {
            Logger.log(message: "⚠️ Quick Preview JSON is not a tiled scene manifest: \(fileURL.lastPathComponent)")
            if fromExploreMode {
                showPreviewImportGallery = true
                pendingQuickPreviewLoadsInExplore = false
            }
            return
        }

        deleteExistingQuickPreviewEntities()
        let existingEntityIds = Set(getAllGameEntities())

        // Create a new entity for the preview
        removeGizmo()
        let entityId = createEntity()

        let uniqueName = "QuickPreview-\(fileName)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        // Mark this entity as a Quick Preview entity (cannot be saved)
        registerComponent(entityId: entityId, componentType: QuickPreviewComponent.self)
        if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId) {
            quickPreviewComp.absoluteFilePath = absolutePath
            quickPreviewComp.fileExtension = fileExtension
            quickPreviewComp.originalFileName = fileName
        }

        if fileExtension == "untold" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            // Load Untold runtime asset using absolute path
            setEntityMeshAsync(entityId: entityId, filename: absolutePath, withExtension: fileExtension) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: fileURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: true,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if fromExploreMode {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
                            } else {
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview loaded: \(fileName).\(fileExtension)")
                    } else {
                        print("⚠️ Failed to load Quick Preview, using fallback: \(fileName).\(fileExtension)")
                        if fromExploreMode {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                }
            }
        } else if fileExtension == "ply" || fileExtension == "untoldgs" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            loadEditorGaussianAuto(entityId: entityId, url: fileURL) { success in
                if success {
                    print("✅ Quick Preview Gaussian loaded: \(fileName).\(fileExtension)")
                } else {
                    print("⚠️ Failed to load Quick Preview Gaussian: \(fileName).\(fileExtension)")
                }
                sceneGraphModel.refreshHierarchy()
            }
            if fromExploreMode == false {
                revealCameraControlHintsIfNeeded()
            }
        } else if fileExtension == "json" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = true

            setEntityStreamScene(entityId: entityId, url: fileURL) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: fileURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: false,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if fromExploreMode {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
                            } else {
                                revealCameraControlHintsIfNeeded()
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview stream model loaded: \(fileName).\(fileExtension)")
                    } else {
                        print("⚠️ Failed to load Quick Preview stream model: \(fileName).\(fileExtension)")
                        if fromExploreMode {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                    sceneGraphModel.refreshHierarchy()
                }
            }

            selectionManager.selectedEntity = entityId
            editor_entities = getAllGameEntities()
            sceneGraphModel.refreshHierarchy()

            print("ℹ️ Quick Preview mode: Stream model loaded with absolute manifest path")
            print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
            return
        }

        // Spawn in front of camera
        guard let camera = CameraSystem.shared.activeCamera,
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera)
        else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: spawnPosition)

        // Select and refresh
        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        if fromExploreMode, fileExtension != "untold" {
            completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
        }

        print("ℹ️ Quick Preview mode: File loaded with absolute path")
        print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
    }

    func loadQuickPreviewSceneAuthored(
        url: URL,
        fileExtension: String,
        isRuntimeAsset: Bool,
        existingEntityIds: Set<EntityID>,
        completion: @escaping (Bool) -> Void
    ) {
        guard fileExtension == "untold" || fileExtension == "json" else {
            completion(false)
            return
        }

        if isRuntimeAsset {
            loadSceneAuthored(filename: url.path, withExtension: fileExtension) { success in
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

    func isConvertibleSourceAsset(_ url: URL) -> Bool {
        ["usd", "usda", "usdc", "usdz", "blend"].contains(url.pathExtension.lowercased())
    }

    func queueQuickPreviewRuntimeExport(sourceURL: URL) {
        let cacheDirectory = QuickPreviewRuntimeExportCache.cacheDirectory(for: sourceURL)
        let outputURL = QuickPreviewRuntimeExportCache.outputURL(for: sourceURL, in: cacheDirectory)

        QuickPreviewRuntimeExportCache.pruneStaleCaches(preserving: [cacheDirectory])

        pendingQuickPreviewExport = QuickPreviewRuntimeExportRequest(
            sourceURL: sourceURL,
            outputURL: outputURL
        )
    }

    func quickPreviewRuntimeExportSheet(for request: QuickPreviewRuntimeExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Convert to Untold Preview Asset")
                .font(.title2)
                .bold()

            Text("This USD or .blend file needs to be converted to Untold Engine's .untold runtime format before it can be previewed.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.top, 6)
                Text(request.outputURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Convert orientation", isOn: $quickPreviewConvertOrientation)

                Picker("Source orientation", selection: $quickPreviewSourceOrientation) {
                    Text("Blender native").tag("blender-native")
                    Text("Engine oriented").tag("engine-oriented")
                }
                .disabled(!quickPreviewConvertOrientation)

                Toggle("Compress geometry (LZ4)", isOn: $quickPreviewCompressGeometry)
                    .help("Compresses vertex and index data with LZ4. Requires the Python lz4 package.")
                if quickPreviewCompressGeometry {
                    Text("Requires: pip install lz4")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .padding(.leading, 20)
                }

                Toggle("Compress textures (ASTC)", isOn: $quickPreviewCompressTextures)
                    .help("Converts textures to GPU-native ASTC format. Requires astcenc and the Python Pillow package.")
                if quickPreviewCompressTextures {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Link("Install astcenc ->", destination: URL(string: "https://github.com/ARM-software/astc-encoder/releases")!)
                                .font(.caption)
                            Text("-")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            Text("Also requires: pip install Pillow")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("astcenc path (optional)")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            HStack {
                                TextField("/opt/homebrew/bin/astcenc", text: $quickPreviewAstcencBinPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.title = "Select astcenc binary"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        quickPreviewAstcencBinPath = url.path
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            if isExportingQuickPreviewAsset {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exporting...")
                        .foregroundColor(.editorTextSecondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingQuickPreviewExport = nil
                }
                .disabled(isExportingQuickPreviewAsset)

                Button("Export and Load") {
                    exportAndLoadQuickPreviewRuntimeAsset(request)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExportingQuickPreviewAsset)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    func exportAndLoadQuickPreviewRuntimeAsset(_ request: QuickPreviewRuntimeExportRequest) {
        guard !isExportingQuickPreviewAsset else { return }
        guard let exporterScript = findExportUntoldScript() else {
            Logger.log(message: "❌ export-untold script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold")
            pendingQuickPreviewExport = nil
            return
        }

        isExportingQuickPreviewAsset = true
        let task = TaskCenter.begin(
            "Quick preview: \(request.sourceURL.lastPathComponent)",
            detail: "Exporting for preview…"
        )
        let convertOrientation = quickPreviewConvertOrientation
        let sourceOrientation = quickPreviewSourceOrientation
        let compressGeometry = quickPreviewCompressGeometry
        let compressTextures = quickPreviewCompressTextures
        let astcencBin = quickPreviewAstcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("quick-preview-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("quick-preview-export-\(UUID().uuidString).err")
            task.attach(process: process)

            do {
                try FileManager.default.createDirectory(at: request.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: request.outputURL.path) {
                    try FileManager.default.removeItem(at: request.outputURL)
                }
                FileManager.default.createFile(atPath: outputLogURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputLogURL)
                let errorHandle = try FileHandle(forWritingTo: errorLogURL)
                defer {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    try? FileManager.default.removeItem(at: outputLogURL)
                    try? FileManager.default.removeItem(at: errorLogURL)
                }

                process.executableURL = exporterScript
                var arguments = [
                    "--input", request.sourceURL.path,
                    "--output", request.outputURL.path,
                ]
                if convertOrientation {
                    arguments.append("--ConvertOrientation")
                    arguments.append(contentsOf: ["--source-orientation", sourceOrientation])
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
                }
                process.arguments = arguments
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                try process.run()
                process.waitUntilExit()

                let stdout = (try? String(contentsOf: outputLogURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errorLogURL, encoding: .utf8)) ?? ""
                let wasCancelled = task.isCancelRequested
                let exportSucceeded = process.terminationStatus == 0 && !wasCancelled

                DispatchQueue.main.async {
                    if !stdout.isEmpty {
                        Logger.log(message: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if !stderr.isEmpty {
                        Logger.log(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                if exportSucceeded, compressTextures {
                    let texturesDir = request.outputURL.deletingLastPathComponent().appendingPathComponent("Textures")
                    if FileManager.default.fileExists(atPath: texturesDir.path),
                       let texbakeScript = findTexbakeScript()
                    {
                        task.setDetail("Baking textures (ASTC)…")
                        let bakeResult = runTexbakeStep(script: texbakeScript, arguments: ["--dir", texturesDir.path], astcencBin: astcencBin)
                        task.setDetail("Patching texture references…")
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !bakeResult.stdout.isEmpty {
                                Logger.log(message: bakeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !bakeResult.stderr.isEmpty {
                                Logger.log(message: bakeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stdout.isEmpty {
                                Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stderr.isEmpty {
                                Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — preview asset exported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                if wasCancelled {
                    task.markCancelled("Cancelled by user")
                } else if exportSucceeded {
                    task.succeed("Loaded into viewport")
                } else {
                    task.fail("export-untold exited with status \(process.terminationStatus) (see Console)")
                }

                DispatchQueue.main.async {
                    isExportingQuickPreviewAsset = false
                    pendingQuickPreviewExport = nil
                    if wasCancelled {
                        QuickPreviewRuntimeExportCache.removeCacheDirectory(at: request.outputURL.deletingLastPathComponent())
                        Logger.log(message: "Quick Preview export cancelled for \(request.sourceURL.lastPathComponent)")
                    } else if exportSucceeded {
                        editor_loadQuickPreviewAsset(from: request.outputURL, originalSourceURL: request.sourceURL)
                    } else {
                        QuickPreviewRuntimeExportCache.removeCacheDirectory(at: request.outputURL.deletingLastPathComponent())
                        Logger.log(message: "❌ Quick Preview export failed for \(request.sourceURL.lastPathComponent)")
                    }
                }
            } catch {
                task.fail(error.localizedDescription)
                DispatchQueue.main.async {
                    isExportingQuickPreviewAsset = false
                    pendingQuickPreviewExport = nil
                    QuickPreviewRuntimeExportCache.removeCacheDirectory(at: request.outputURL.deletingLastPathComponent())
                    Logger.log(message: "❌ Quick Preview export failed: \(error)")
                }
            }
        }
    }

    func editor_loadQuickPreviewAsset(from loadURL: URL, originalSourceURL: URL? = nil) {
        let sourceURL = originalSourceURL ?? loadURL
        let fileExtension = loadURL.pathExtension.lowercased()
        let absolutePath = loadURL.path
        let fileName = sourceURL.deletingPathExtension().lastPathComponent

        deleteExistingQuickPreviewEntities()
        let existingEntityIds = Set(getAllGameEntities())
        removeGizmo()

        let entityId = createEntity()
        let uniqueName = "QuickPreview-\(fileName)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        registerComponent(entityId: entityId, componentType: QuickPreviewComponent.self)
        if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId) {
            quickPreviewComp.absoluteFilePath = sourceURL.path
            quickPreviewComp.fileExtension = sourceURL.pathExtension.lowercased()
            quickPreviewComp.originalFileName = fileName
            if originalSourceURL != nil {
                quickPreviewComp.runtimePreviewDirectoryPath = loadURL.deletingLastPathComponent().path
            }
        }

        if fileExtension == "untold" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            setEntityMeshAsync(entityId: entityId, filename: absolutePath, withExtension: fileExtension) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: loadURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: true,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if pendingQuickPreviewLoadsInExplore {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: .untoldAsset)
                            } else {
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview loaded: \(loadURL.lastPathComponent)")
                    } else {
                        print("⚠️ Failed to load Quick Preview, using fallback: \(loadURL.lastPathComponent)")
                        if pendingQuickPreviewLoadsInExplore {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                }
            }
        } else if fileExtension == "ply" || fileExtension == "untoldgs" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            loadEditorGaussianAuto(entityId: entityId, url: loadURL) { success in
                if success {
                    print("✅ Quick Preview Gaussian loaded: \(loadURL.lastPathComponent)")
                } else {
                    print("⚠️ Failed to load Quick Preview Gaussian: \(loadURL.lastPathComponent)")
                }
                sceneGraphModel.refreshHierarchy()
            }
        }

        guard let camera = CameraSystem.shared.activeCamera,
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera)
        else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: spawnPosition)

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        if pendingQuickPreviewLoadsInExplore, fileExtension != "untold" {
            completeExploreQuickPreviewLoad(fileName: fileName, mode: .untoldAsset)
        }

        print("ℹ️ Quick Preview mode: File loaded with absolute path")
        print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
    }

    func completeExploreQuickPreviewLoad(fileName: String, mode: QuickPreviewImportMode) {
        experienceMode = .explore
        showWelcomeStart = true
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = nil
        activeDemoCameraFrame = nil
        activePreviewSceneTitle = fileName
        activePreviewImportMode = mode
        pendingQuickPreviewLoadsInExplore = false
        clearExploreSelection()
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        enableExploreNavigationMode()
        revealCameraControlHintsIfNeeded()
    }

    func deleteExistingQuickPreviewEntities() {
        let previewEntityIds = getAllGameEntities()
            .filter { hasComponent(entityId: $0, componentType: QuickPreviewComponent.self) }

        guard previewEntityIds.isEmpty == false else {
            return
        }

        for entityId in previewEntityIds {
            if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId),
               quickPreviewComp.runtimePreviewDirectoryPath.isEmpty == false
            {
                QuickPreviewRuntimeExportCache.removeCacheDirectory(at: URL(fileURLWithPath: quickPreviewComp.runtimePreviewDirectoryPath))
            }
            EditorGaussianAssetState.shared.clear(entityId: entityId)
            destroyEntity(entityId: entityId)
        }

        if let selectedId = selectionManager.selectedEntity,
           previewEntityIds.contains(selectedId)
        {
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
        }

        editor_entities = getAllGameEntities()
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()
    }

    // MARK: - Quick Preview Save Validation

    /// Checks if the scene contains any Quick Preview entities.
    /// Returns true if Quick Preview entities exist (and shows warning), false otherwise.
    func checkForQuickPreviewEntities() -> Bool {
        var foundEntities: [(EntityID, String)] = []

        // Scan all entities for QuickPreviewComponent
        for entityId in getAllGameEntities() {
            if hasComponent(entityId: entityId, componentType: QuickPreviewComponent.self) {
                let entityName = getEntityName(entityId: entityId)
                let displayName = entityName.isEmpty ? "Entity \(entityId)" : entityName
                foundEntities.append((entityId, displayName))
            }
        }

        if !foundEntities.isEmpty {
            quickPreviewEntities = foundEntities
            showQuickPreviewWarning = true
            return true
        }

        return false
    }

    /// Deletes all Quick Preview entities and proceeds with save.
    func deleteQuickPreviewEntitiesAndSave() {
        // Delete all Quick Preview entities
        for (entityId, entityName) in quickPreviewEntities {
            if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId),
               quickPreviewComp.runtimePreviewDirectoryPath.isEmpty == false
            {
                QuickPreviewRuntimeExportCache.removeCacheDirectory(at: URL(fileURLWithPath: quickPreviewComp.runtimePreviewDirectoryPath))
            }
            destroyEntity(entityId: entityId)
            print("🗑️ Deleted Quick Preview entity: \(entityName)")
        }

        // Refresh UI
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()

        // Clear selection if it was a Quick Preview entity
        if let selectedId = selectionManager.selectedEntity,
           quickPreviewEntities.contains(where: { $0.0 == selectedId })
        {
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            removeGizmo()
        }

        quickPreviewEntities = []

        // Now proceed with the save
        if isSaveAs {
            // Re-trigger Save As flow
            editor_handleSaveAs()
        } else {
            // Re-trigger Save flow
            editor_handleSave()
        }
    }
}
