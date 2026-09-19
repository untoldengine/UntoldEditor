//
//  EditorGaussianAssetState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UntoldEngine

enum EditorGaussianLoadPlan: Equatable {
    case single(filename: String, withExtension: String)
    case progressive(baseFilename: String, levelCount: Int, maxDistances: [Float])
}

enum EditorGaussianLoadingMode: String, CaseIterable, Equatable {
    case resident = "Resident"
    case streaming = "Streaming"
}

struct EditorGaussianStreamingSettings: Equatable {
    var streamingRadius: Float = 100
    var unloadRadius: Float = 150
    var priority: Int = 0
}

struct EditorGaussianAssetMetadata: Equatable {
    let sourceURL: URL
    let plan: EditorGaussianLoadPlan
    var loadingMode: EditorGaussianLoadingMode = .resident
    var streamingSettings = EditorGaussianStreamingSettings()

    var progressiveLevelCount: Int? {
        guard case let .progressive(_, levelCount, _) = plan else { return nil }
        return levelCount
    }

    var progressiveMaxDistances: [Float]? {
        guard case let .progressive(_, _, maxDistances) = plan else { return nil }
        return maxDistances
    }
}

final class EditorGaussianAssetState {
    static let shared = EditorGaussianAssetState()

    private var metadataByEntity: [EntityID: EditorGaussianAssetMetadata] = [:]

    func metadata(for entityId: EntityID) -> EditorGaussianAssetMetadata? {
        metadataByEntity[entityId]
    }

    func setMetadata(_ metadata: EditorGaussianAssetMetadata, for entityId: EntityID) {
        metadataByEntity[entityId] = metadata
    }

    func clear(entityId: EntityID) {
        metadataByEntity[entityId] = nil
    }

    func clear() {
        metadataByEntity.removeAll()
    }
}

/// The editor's default Gaussian policy: progressive tier sets load as resident LOD assets;
/// every other .ply/.untoldgs loads as a single resident asset off the main thread.
func editorGaussianLoadPlan(for url: URL, maxDistances: [Float]? = nil) -> EditorGaussianLoadPlan? {
    let ext = url.pathExtension.lowercased()
    guard ext == "ply" || ext == "untoldgs" else { return nil }

    if ext == "untoldgs", let tiers = progressiveGaussianTiers(for: url) {
        let distances = editorNormalizedGaussianLODDistances(
            maxDistances ?? defaultGaussianLODDistances(levelCount: tiers.levelCount),
            levelCount: tiers.levelCount
        )
        return .progressive(
            baseFilename: tiers.baseURL.path,
            levelCount: tiers.levelCount,
            maxDistances: distances
        )
    }

    return .single(
        filename: url.deletingPathExtension().path,
        withExtension: ext
    )
}

/// `info.baseFilename` is whatever project-relative-or-absolute identifier the scene file
/// happened to store (see `GaussianSceneData.baseFilename` in the engine's `SceneSerializer`) —
/// not necessarily an absolute path, unlike every `EditorGaussianLoadPlan.progressive` built
/// from a fresh pick via `editorGaussianLoadPlan(for:maxDistances:)`, which always derives
/// `baseFilename` from a resolved file URL. Reconstructs that same absolute-path shape instead,
/// from the tier-0 URL the engine already resolved onto the just-restored entity's
/// `GaussianLODComponent` — cheap string manipulation, no disk probing (unlike
/// `progressiveGaussianTiers(for:)`, which counts tiers by checking file existence).
private func resolvedProgressiveBaseFilename(entityId: EntityID, levelCount: Int) -> String? {
    guard let tierZeroURL = scene.get(component: GaussianLODComponent.self, for: entityId)?.lodLevels.first?.url else {
        return nil
    }
    let noExtension = tierZeroURL.deletingPathExtension()
    let name = noExtension.lastPathComponent
    guard levelCount > 1, name.hasSuffix("_lod0") else {
        return noExtension.path
    }
    let baseName = String(name.dropLast("_lod0".count))
    return noExtension.deletingLastPathComponent().appendingPathComponent(baseName).path
}

/// Rebuilds this entity's `EditorGaussianAssetState` entry from what `deserializeScene` already
/// resolved for it, so the Inspector's Gaussian panel reflects a splat restored from a
/// `.untoldscene` the same way it reflects one just dropped or assigned interactively —
/// without re-reading the asset off disk. Pass as `deserializeScene`'s
/// `onGaussianEntityRestored` callback.
func restoreEditorGaussianState(entityId: EntityID, info: GaussianSceneRestoreInfo) {
    let plan: EditorGaussianLoadPlan
    if info.isProgressive, let levelCount = info.levelCount, let maxDistances = info.maxDistances,
       let baseFilename = resolvedProgressiveBaseFilename(entityId: entityId, levelCount: levelCount)
    {
        plan = .progressive(baseFilename: baseFilename, levelCount: levelCount, maxDistances: maxDistances)
    } else {
        plan = .single(filename: info.sourceURL.deletingPathExtension().path, withExtension: info.fileExtension)
    }

    EditorGaussianAssetState.shared.setMetadata(
        EditorGaussianAssetMetadata(sourceURL: info.sourceURL, plan: plan),
        for: entityId
    )
}

@discardableResult
func loadEditorGaussianAuto(
    entityId: EntityID,
    url: URL,
    maxDistances: [Float]? = nil,
    loadingMode: EditorGaussianLoadingMode = .resident,
    streamingSettings: EditorGaussianStreamingSettings = EditorGaussianStreamingSettings(),
    completion: ((Bool) -> Void)? = nil
) -> Bool {
    guard let plan = editorGaussianLoadPlan(for: url, maxDistances: maxDistances) else {
        completion?(false)
        return false
    }

    if loadingMode == .streaming {
        return loadEditorGaussianStreaming(
            entityId: entityId,
            url: url,
            plan: plan,
            streamingSettings: streamingSettings,
            completion: completion
        )
    }

    // A whole-resident load of a large file takes seconds with nothing on screen: the Tasks
    // panel shows it, with what the engine is about to do with the file.
    let task = TaskCenter.begin("Loading \(url.lastPathComponent)", detail: "Reading \(url.lastPathComponent)")

    switch plan {
    case let .progressive(baseFilename, levelCount, maxDistances):
        // The engine has no asynchronous progressive loader: the tiers read on the main thread.
        task.setDetail("\(levelCount) progressive tiers, resident")
        removeEntityGaussian(entityId: entityId)
        scene.remove(component: StreamingComponent.self, from: entityId)
        setEntityGaussian(
            entityId: entityId,
            source: .progressive(
                baseFilename: baseFilename,
                levelCount: levelCount,
                maxDistances: maxDistances
            )
        )
        EditorGaussianAssetState.shared.setMetadata(
            EditorGaussianAssetMetadata(
                sourceURL: url,
                plan: plan,
                loadingMode: .resident,
                streamingSettings: streamingSettings
            ),
            for: entityId
        )
        task.succeed()
        completion?(true)
        return true

    case let .single(filename, withExtension):
        Task {
            // The index read (header, chunk table, tree) is bounded; the payload comes through
            // the engine's loader below, off the main thread.
            let detail = await Task.detached { gaussianPlacementDetail(for: url) }.value
            task.setDetail(detail)
            let success = await setEntityGaussianAsync(entityId: entityId, url: url)
            DispatchQueue.main.async {
                if success {
                    task.succeed(detail)
                } else {
                    task.fail("The engine declined \(url.lastPathComponent) (see Console)")
                }
                if success {
                    EditorGaussianAssetState.shared.setMetadata(
                        EditorGaussianAssetMetadata(
                            sourceURL: url,
                            plan: .single(filename: filename, withExtension: withExtension),
                            loadingMode: .resident,
                            streamingSettings: streamingSettings
                        ),
                        for: entityId
                    )
                } else {
                    EditorGaussianAssetState.shared.clear(entityId: entityId)
                }
                completion?(success)
            }
        }
        return true
    }
}

private func loadEditorGaussianStreaming(
    entityId: EntityID,
    url: URL,
    plan: EditorGaussianLoadPlan,
    streamingSettings: EditorGaussianStreamingSettings,
    completion: ((Bool) -> Void)?
) -> Bool {
    let normalizedSettings = editorNormalizedGaussianStreamingSettings(streamingSettings)
    guard GeometryStreamingSystem.shared.enabled else {
        Logger.logWarning(message: "[Gaussian] Streaming mode requires an active streamed scene.")
        completion?(false)
        return false
    }

    guard url.pathExtension.lowercased() == "untoldgs" else {
        Logger.logWarning(message: "[Gaussian] Streaming mode requires a baked .untoldgs asset.")
        completion?(false)
        return false
    }

    scene.remove(component: StreamingComponent.self, from: entityId)

    let source: GaussianSource
    switch plan {
    case let .single(filename, withExtension):
        source = .single(filename: filename, withExtension: withExtension)
    case let .progressive(baseFilename, levelCount, maxDistances):
        source = .progressive(
            baseFilename: baseFilename,
            levelCount: levelCount,
            maxDistances: maxDistances
        )
    }

    setEntityGaussianTileStreaming(
        entityId: entityId,
        source: source,
        options: GaussianStreamingOptions(
            streamingRadius: normalizedSettings.streamingRadius,
            unloadRadius: normalizedSettings.unloadRadius,
            priority: normalizedSettings.priority
        )
    )

    let registered = scene.get(component: StreamingComponent.self, for: entityId)?.assetKind == .gaussianSplat
    if registered {
        if case .single = plan {
            removeEntityGaussian(entityId: entityId)
        }
        EditorGaussianAssetState.shared.setMetadata(
            EditorGaussianAssetMetadata(
                sourceURL: url,
                plan: plan,
                loadingMode: .streaming,
                streamingSettings: normalizedSettings
            ),
            for: entityId
        )
    } else {
        Logger.logWarning(message: "[Gaussian] Failed to register streaming Gaussian. Move the entity inside a streamed tile and try again.")
    }
    completion?(registered)
    return registered
}

func editorNormalizedGaussianStreamingSettings(_ settings: EditorGaussianStreamingSettings) -> EditorGaussianStreamingSettings {
    let streamingRadius = max(settings.streamingRadius, Float.leastNonzeroMagnitude)
    return EditorGaussianStreamingSettings(
        streamingRadius: streamingRadius,
        unloadRadius: max(settings.unloadRadius, streamingRadius + 0.001),
        priority: settings.priority
    )
}

func editorNormalizedGaussianLODDistances(_ distances: [Float], levelCount: Int) -> [Float] {
    guard levelCount > 0 else { return [] }
    let defaults = defaultGaussianLODDistances(levelCount: levelCount)
    var normalized = (0 ..< levelCount).map { index in
        index < distances.count ? distances[index] : defaults[index]
    }

    for index in 0 ..< max(0, levelCount - 1) {
        let minimum = index == 0 ? Float.leastNonzeroMagnitude : normalized[index - 1] + 0.001
        if normalized[index].isFinite == false || normalized[index] < minimum {
            normalized[index] = minimum
        }
    }
    normalized[levelCount - 1] = .greatestFiniteMagnitude
    return normalized
}

func updateEditorGaussianLODDistance(entityId: EntityID, lodIndex: Int, maxDistance: Float) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId),
          let levelCount = metadata.progressiveLevelCount,
          var distances = metadata.progressiveMaxDistances,
          lodIndex >= 0,
          lodIndex < levelCount - 1
    else { return false }

    distances[lodIndex] = maxDistance
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: distances,
        loadingMode: metadata.loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func resetEditorGaussianLODDistances(entityId: EntityID) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId),
          let levelCount = metadata.progressiveLevelCount
    else { return false }

    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: defaultGaussianLODDistances(levelCount: levelCount),
        loadingMode: metadata.loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func updateEditorGaussianLoadingMode(entityId: EntityID, loadingMode: EditorGaussianLoadingMode) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) else { return false }
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: metadata.progressiveMaxDistances,
        loadingMode: loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func updateEditorGaussianStreamingSettings(entityId: EntityID, settings: EditorGaussianStreamingSettings) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) else { return false }
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: metadata.progressiveMaxDistances,
        loadingMode: metadata.loadingMode,
        streamingSettings: settings
    )
}
