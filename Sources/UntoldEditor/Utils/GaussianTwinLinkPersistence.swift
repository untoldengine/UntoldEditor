//
//  GaussianTwinLinkPersistence.swift
//  UntoldEditor
//
//  Where the Inspector's Splat Twin section reads and writes a mesh entity's link to its
//  cooked `.untoldgs` twin: the `gaussianAsset` record of the `.untold` file the entity was
//  placed from, patched through the engine's `UntoldAssetPatcher`, mirrored onto the live
//  `GaussianAssetLinkComponent` of every entity backed by that record, and previewed in the
//  viewport through `UntoldGaussianTwins` while the View > Preview Splat Twins toggle is on.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldEngine
import UntoldGaussianTwins

/// The `.untold` file and the entity-table record a scene entity's twin link is stored in.
struct GaussianTwinLinkTarget: Equatable {
    let untoldURL: URL
    /// `UntoldEntityRecordV1.entityId` of the record: the key of the `gaussianAsset` table.
    let entityRecordId: UInt32
}

enum GaussianTwinLinkError: LocalizedError, Equatable {
    /// The entity is not a mesh placed from a `.untold` file (a primitive, a light, a splat).
    case notBackedByUntold
    /// The entity is backed by a `.untold` file whose entity table has no record for it — the
    /// root of a multi-node asset, or an asset re-exported since it was placed.
    case noEntityRecord(URL)
    /// The entity carries one node of a file with several mesh nodes and none of them is
    /// named like the entity, so the record cannot be told apart.
    case ambiguousEntityRecord(URL)
    case payloadNotFound(URL)
    /// Not a version 3 `.untoldgs`; the reason is the engine's.
    case invalidPayload(URL, String)
    case readFailed(URL, String)
    case patchFailed(String)
    case writeFailed(URL, String)

    var errorDescription: String? {
        switch self {
        case .notBackedByUntold:
            return "Only meshes placed from a .untold asset can have a splat twin."
        case let .noEntityRecord(url):
            return "\(url.lastPathComponent) has no entity record for this node; select one of its mesh nodes."
        case let .ambiguousEntityRecord(url):
            return "\(url.lastPathComponent) has several mesh nodes and none is named like this entity; place the asset again and select the mesh node."
        case let .payloadNotFound(url):
            return "Payload not found: \(url.path)"
        case let .invalidPayload(url, reason):
            return "\(url.lastPathComponent) is not a usable .untoldgs payload: \(reason). Cook the source with Cook to .untoldgs… first."
        case let .readFailed(url, reason):
            return "Could not read \(url.lastPathComponent): \(reason)"
        case let .patchFailed(reason):
            return reason
        case let .writeFailed(url, reason):
            return "Could not write \(url.lastPathComponent): \(reason)"
        }
    }
}

extension Notification.Name {
    /// Posted after a twin link was written to or removed from a `.untold` file. `userInfo`
    /// carries `GaussianTwinLinkPersistence.targetUserInfoKey` → `GaussianTwinLinkTarget`;
    /// `object` is the writer that asked for the change (nil for the undo stack), so a model
    /// can tell its own writes from another's.
    static let gaussianTwinLinkDidChange = Notification.Name("gaussianTwinLinkDidChange")
}

enum GaussianTwinLinkPersistence {
    static let targetUserInfoKey = "target"

    /// Whether the viewport preview is on. The live editor reads the View menu toggle; tests
    /// pin it without touching `UserDefaults.standard`.
    nonisolated(unsafe) static var previewEnabled: () -> Bool = { GaussianTwinPreviewSettings.shared.isEnabled }

    // MARK: - Target resolution

    /// The `.untold` file and entity record a scene entity's link lives in, or nil when the
    /// entity is not backed by a `.untold` file. The root of a single-node asset maps to the
    /// file's mesh-bearing record; a derived mesh node maps to the record whose node path
    /// matches its `DerivedAssetNodeComponent`. The root of a multi-node asset carries no
    /// mesh of its own and is not a target (its nodes are). Reads and decodes the file.
    static func resolveTarget(entityId: EntityID) -> GaussianTwinLinkTarget? {
        try? resolveTargetOrThrow(entityId: entityId)
    }

    static func resolveTargetOrThrow(entityId: EntityID) throws -> GaussianTwinLinkTarget {
        try loadTarget(entityId: entityId).target
    }

    /// `resolveTargetOrThrow` handing back the decoded file as well, so a caller that reads the
    /// link or the entity table next does not decode it twice.
    static func loadTarget(entityId: EntityID) throws -> (target: GaussianTwinLinkTarget, decoded: UntoldDecodedAsset) {
        guard let untoldURL = resolveUntoldURL(entityId: entityId) else {
            throw GaussianTwinLinkError.notBackedByUntold
        }
        let decoded = try readDecodedAsset(at: untoldURL)
        let target = try resolveTarget(entityId: entityId, untoldURL: untoldURL, decoded: decoded)
        return (target, decoded)
    }

    /// `resolveTargetOrThrow` on an already decoded file.
    static func resolveTarget(entityId: EntityID, untoldURL: URL, decoded: UntoldDecodedAsset) throws -> GaussianTwinLinkTarget {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self) else {
            throw GaussianTwinLinkError.notBackedByUntold
        }
        switch resolveEntityRecord(entityId: entityId, decoded: decoded) {
        case nil:
            throw GaussianTwinLinkError.noEntityRecord(untoldURL)
        case .ambiguous?:
            throw GaussianTwinLinkError.ambiguousEntityRecord(untoldURL)
        case let .record(record)?:
            return GaussianTwinLinkTarget(untoldURL: untoldURL, entityRecordId: record.entityId)
        }
    }

    private enum EntityRecordResolution {
        case record(UntoldEntityRecordV1)
        case ambiguous
    }

    /// The entity record an entity's link is keyed by. A derived node resolves through its node
    /// path (`resolveEntityRecordForMesh`). A plain mesh entity was given one node of the file
    /// by the engine: the only mesh-bearing record when there is one, else the record named
    /// like the entity (the engine names the entity after the node it registered); with
    /// several mesh nodes and no unique name match nothing is guessed.
    private static func resolveEntityRecord(entityId: EntityID, decoded: UntoldDecodedAsset) -> EntityRecordResolution? {
        if isDerivedAssetNode(entityId) {
            return resolveEntityRecordForMesh(entityId: entityId, meshIndex: 0, decoded: decoded).map { .record($0) }
        }
        let meshBearing = decoded.entities.filter { $0.meshRecordCount > 0 }
        if meshBearing.count <= 1 {
            return meshBearing.first.map { .record($0) }
        }
        let entityName = getEntityName(entityId: entityId)
        let named = meshBearing.filter { record in
            ((try? decoded.string(at: record.nameOffset)) ?? nil) == entityName
        }
        return named.count == 1 ? .record(named[0]) : .ambiguous
    }

    /// The `.untold` file behind a mesh entity, without reading it: the asset instance's file
    /// for a derived mesh node, the render component's for a single-node asset root. Nil for
    /// a multi-node asset root (no mesh of its own), a derived node without a mesh, a streamed
    /// stub (its node path is the streamer's, not the file's, so no record can be matched) and
    /// anything not placed from a `.untold` file.
    static func resolveUntoldURL(entityId: EntityID) -> URL? {
        guard hasComponent(entityId: entityId, componentType: RenderComponent.self),
              !hasComponent(entityId: entityId, componentType: StreamingComponent.self)
        else { return nil }
        if isDerivedAssetNode(entityId), isBindableAssetMeshNode(entityId) == false {
            return nil
        }
        return resolveUntoldAssetURL(entityId: entityId)?.standardizedFileURL
    }

    // MARK: - Reading

    /// The link the entity's `.untold` record carries, nil when there is none (or the entity
    /// resolves to no target).
    static func readTwinLink(entityId: EntityID) -> UntoldAssetPatcher.GaussianAssetLink? {
        guard let loaded = try? loadTarget(entityId: entityId) else { return nil }
        return try? readTwinLink(target: loaded.target, decoded: loaded.decoded)
    }

    static func readTwinLink(target: GaussianTwinLinkTarget) throws -> UntoldAssetPatcher.GaussianAssetLink? {
        let fileData = try readFileData(at: target.untoldURL)
        do {
            return try UntoldAssetPatcher.gaussianAssets(in: fileData)[target.entityRecordId]
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
    }

    /// `readTwinLink(target:)` on an already decoded file: the first record of the entity,
    /// as `UntoldAssetPatcher.gaussianAssets(in:)` and the loader keep it.
    static func readTwinLink(target: GaussianTwinLinkTarget, decoded: UntoldDecodedAsset) throws -> UntoldAssetPatcher.GaussianAssetLink? {
        guard let record = decoded.gaussianAssets.first(where: { $0.entityId == target.entityRecordId }) else {
            return nil
        }
        guard let path = try? decoded.string(at: record.payloadPathOffset) else {
            throw GaussianTwinLinkError.patchFailed("gaussianAsset record for entity \(record.entityId) has no payload path")
        }
        return UntoldAssetPatcher.GaussianAssetLink(record: record, payloadPath: path)
    }

    // MARK: - Writing

    /// Writes `link` as the record of the entity's `.untold` target (atomically), mirrors it
    /// onto the `GaussianAssetLinkComponent` of this entity and of every other scene entity
    /// backed by the same file and record, and updates the viewport preview when it is on.
    static func writeTwinLink(entityId: EntityID, link: UntoldAssetPatcher.GaussianAssetLink) throws {
        let target = try resolveTargetOrThrow(entityId: entityId)
        try writeTwinLink(target: target, link: link)
    }

    /// `writer` is handed to `.gaussianTwinLinkDidChange` as its object.
    static func writeTwinLink(target: GaussianTwinLinkTarget, link: UntoldAssetPatcher.GaussianAssetLink, writer: AnyObject? = nil) throws {
        let fileData = try readFileData(at: target.untoldURL)
        let patched: Data
        do {
            patched = try UntoldAssetPatcher.settingGaussianAsset(link, onEntity: target.entityRecordId, in: fileData)
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
        try write(patched, to: target.untoldURL)
        // The entity table is untouched by the patch, so the bytes just read describe it.
        applyToScene(target: target, link: link, decoded: try? decodeAsset(fileData, at: target.untoldURL), writer: writer)
    }

    /// Removes the entity's record from its `.untold` target, the `GaussianAssetLinkComponent`
    /// from every entity backed by it, and the previewed twin.
    static func removeTwinLink(entityId: EntityID) throws {
        let target = try resolveTargetOrThrow(entityId: entityId)
        try removeTwinLink(target: target)
    }

    static func removeTwinLink(target: GaussianTwinLinkTarget, writer: AnyObject? = nil) throws {
        let fileData = try readFileData(at: target.untoldURL)
        let patched: Data
        do {
            patched = try UntoldAssetPatcher.removingGaussianAsset(onEntity: target.entityRecordId, in: fileData)
        } catch let error as UntoldAssetPatcher.Error {
            throw GaussianTwinLinkError.patchFailed(error.description)
        }
        if patched != fileData {
            try write(patched, to: target.untoldURL)
        }
        applyToScene(target: target, link: nil, decoded: try? decodeAsset(fileData, at: target.untoldURL), writer: writer)
    }

    /// Writes or removes according to `link`; the undo stack restores whole links through this.
    static func restoreTwinLink(target: GaussianTwinLinkTarget, link: UntoldAssetPatcher.GaussianAssetLink?) throws {
        if let link {
            try writeTwinLink(target: target, link: link)
        } else {
            try removeTwinLink(target: target)
        }
    }

    // MARK: - Link construction

    /// The path written into the record, relative to the `.untold` file's directory: a payload
    /// inside it keeps its sub-path (`splats/chair.untoldgs`), one elsewhere on the same volume
    /// climbs to the common ancestor (`../../Gaussians/chair.untoldgs`, the project's Gaussians
    /// folder seen from `Models/Chair/`). Only a payload sharing no ancestor below the root —
    /// another volume — is stored by its bare file name, which the runtime resolves next to the
    /// `.untold` file it loads, so the caller should warn. The paths are compared as given
    /// first, so a payload reached through a symlinked folder keeps that working relative
    /// path; only when that fails are symlinks resolved on both sides.
    static func storedPayloadPath(payloadURL: URL, untoldURL: URL) -> (path: String, isRelative: Bool) {
        let directory = untoldURL.deletingLastPathComponent().standardizedFileURL
        let payload = payloadURL.standardizedFileURL
        if let relative = relativePath(of: payload, from: directory) {
            return (relative, true)
        }
        if let relative = relativePath(of: payload.resolvingSymlinksInPath(), from: directory.resolvingSymlinksInPath()) {
            return (relative, true)
        }
        return (payloadURL.lastPathComponent, false)
    }

    /// `file` relative to `directory` over their longest common prefix; nil when they share
    /// nothing but the root (or `file` is not below the common ancestor).
    private static func relativePath(of file: URL, from directory: URL) -> String? {
        let directory = directory.pathComponents
        let file = file.pathComponents
        var common = 0
        while common < directory.count, common < file.count, directory[common] == file[common] {
            common += 1
        }
        guard common > 1, common < file.count else {
            return nil
        }
        let ascents = Array(repeating: "..", count: directory.count - common)
        return (ascents + file[common...]).joined(separator: "/")
    }

    /// The link for a payload: the file must be a version 3 `.untoldgs`; its header fills one
    /// LOD level with the file's splat count. Settings default to the record's defaults;
    /// `alignment` nil is identity (no alignment flag in the record).
    static func makeLink(
        payloadURL: URL,
        untoldURL: URL,
        swapDistanceMeters: Float = 0,
        occluderShrinkMeters: Float = 0.02,
        exposureOffsetEV: Float = 0,
        alignment: GaussianSplatAlignment? = nil
    ) throws -> UntoldAssetPatcher.GaussianAssetLink {
        guard FileManager.default.fileExists(atPath: payloadURL.path) else {
            throw GaussianTwinLinkError.payloadNotFound(payloadURL)
        }
        let header: UntoldGSHeaderV3
        do {
            header = try UntoldGSFormat.readHeaderV3(from: payloadURL)
        } catch let error as UntoldGSError {
            throw GaussianTwinLinkError.invalidPayload(payloadURL, error.description)
        } catch {
            throw GaussianTwinLinkError.invalidPayload(payloadURL, error.localizedDescription)
        }
        return UntoldAssetPatcher.GaussianAssetLink(
            payloadPath: storedPayloadPath(payloadURL: payloadURL, untoldURL: untoldURL).path,
            flags: UntoldGaussianAssetFlags.meshTwin,
            lodCount: 1,
            lodSplatCounts: [header.splatCount],
            lodSwitchScreenHeights: [0],
            occluderShrinkMeters: occluderShrinkMeters,
            exposureOffsetEV: exposureOffsetEV,
            swapDistanceMeters: swapDistanceMeters,
            alignment: alignment
        )
    }

    /// Where a stored payload path points when the `.untold` file is loaded, by the engine
    /// loader's rules (`NativeFormatLoader.resolvedURL`): a string with a URL scheme
    /// (`file:///…`) as is, anything else next to the `.untold` file — a plain `/abs/…` path is
    /// relative too — and the bare file name beside the file when that does not exist. The
    /// result is standardized (`..` folded) so equal files compare equal.
    static func resolvedPayloadURL(path: String, untoldURL: URL) -> URL {
        if let absolute = URL(string: path), absolute.scheme != nil {
            return absolute
        }
        let directory = untoldURL.deletingLastPathComponent()
        let relative = directory.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: relative.path) {
            return relative.standardizedFileURL
        }
        let basename = (path as NSString).lastPathComponent
        let flattened = directory.appendingPathComponent(basename)
        return FileManager.default.fileExists(atPath: flattened.path) ? flattened.standardizedFileURL : relative.standardizedFileURL
    }

    // MARK: - Scene mirroring

    /// Every scene entity whose link lives in `target`: the selected node and any other
    /// placement of the same asset. Reads the file; `entitiesBacked(by:decoded:)` does not.
    static func entitiesBacked(by target: GaussianTwinLinkTarget) -> [EntityID] {
        guard let decoded = try? readDecodedAsset(at: target.untoldURL) else { return [] }
        return entitiesBacked(by: target, decoded: decoded)
    }

    static func entitiesBacked(by target: GaussianTwinLinkTarget, decoded: UntoldDecodedAsset) -> [EntityID] {
        let renderId = getComponentId(for: RenderComponent.self)
        return queryEntitiesWithComponentIds([renderId], in: scene).filter { entityId in
            guard resolveUntoldURL(entityId: entityId) == target.untoldURL,
                  case let .record(record)? = resolveEntityRecord(entityId: entityId, decoded: decoded)
            else { return false }
            return record.entityId == target.entityRecordId
        }
    }

    /// Mirrors the persisted record onto the live scene (`GaussianAssetLinkComponent` and the
    /// preview) for every entity backed by `target`, then posts `.gaussianTwinLinkDidChange`
    /// with `writer` as its object. Reads the file when `decoded` is nil.
    static func applyToScene(
        target: GaussianTwinLinkTarget,
        link: UntoldAssetPatcher.GaussianAssetLink?,
        decoded: UntoldDecodedAsset? = nil,
        writer: AnyObject? = nil
    ) {
        let backed = decoded.map { entitiesBacked(by: target, decoded: $0) } ?? entitiesBacked(by: target)
        for entityId in backed {
            applyLinkComponent(link, to: entityId, untoldURL: target.untoldURL)
            applyPreview(entityId: entityId)
        }
        NotificationCenter.default.post(
            name: .gaussianTwinLinkDidChange,
            object: writer,
            userInfo: [targetUserInfoKey: target]
        )
    }

    /// Sets (or removes, for nil) the `GaussianAssetLinkComponent` the engine loader would
    /// have attached had the file carried `link` when the entity was placed.
    static func applyLinkComponent(_ link: UntoldAssetPatcher.GaussianAssetLink?, to entityId: EntityID, untoldURL: URL) {
        guard let link else {
            if hasComponent(entityId: entityId, componentType: GaussianAssetLinkComponent.self) {
                scene.remove(component: GaussianAssetLinkComponent.self, from: entityId)
            }
            return
        }
        if scene.get(component: GaussianAssetLinkComponent.self, for: entityId) == nil {
            registerComponent(entityId: entityId, componentType: GaussianAssetLinkComponent.self)
        }
        guard let component = scene.get(component: GaussianAssetLinkComponent.self, for: entityId) else { return }
        component.payloadURL = resolvedPayloadURL(path: link.payloadPath, untoldURL: untoldURL)
        component.flags = link.flags
        component.lodCount = link.lodCount
        component.lodSplatCounts = link.lodSplatCounts
        component.lodSwitchScreenHeights = link.lodSwitchScreenHeights
        component.occluderShrinkMeters = link.occluderShrinkMeters
        component.exposureOffsetEV = link.exposureOffsetEV
        component.swapDistanceMeters = link.swapDistanceMeters
        component.alignment = link.alignment
    }

    /// Whether `entityId` already carries what `applyLinkComponent(link, …)` would set: no
    /// component for a nil link, else one with the same payload (as resolved), flags, LOD
    /// table, margin, exposure offset, swap distance and alignment.
    static func linkComponentMatches(_ link: UntoldAssetPatcher.GaussianAssetLink?, on entityId: EntityID, untoldURL: URL) -> Bool {
        let component = scene.get(component: GaussianAssetLinkComponent.self, for: entityId)
        guard let link else { return component == nil }
        guard let component else { return false }
        return component.payloadURL == resolvedPayloadURL(path: link.payloadPath, untoldURL: untoldURL)
            && component.flags == link.flags
            && component.lodCount == link.lodCount
            && component.lodSplatCounts == link.lodSplatCounts
            && component.lodSwitchScreenHeights == link.lodSwitchScreenHeights
            && component.occluderShrinkMeters == link.occluderShrinkMeters
            && component.exposureOffsetEV == link.exposureOffsetEV
            && component.swapDistanceMeters == link.swapDistanceMeters
            && component.alignment == link.alignment
    }

    /// The options the viewport twin of `entityId` runs: the link's, forced to show the twin
    /// over the mesh while the entity is in align mode (`GaussianTwinAlignMode`).
    static func previewOptions(entityId: EntityID, link component: GaussianAssetLinkComponent) -> GaussianTwinOptions {
        GaussianTwinAlignMode.shared.previewOptions(for: entityId, options: GaussianTwinOptions(link: component))
    }

    /// Brings the viewport twin in line with the entity's `GaussianAssetLinkComponent` and the
    /// align mode (`previewOptions`). A twin that exists is always kept in step, whether the
    /// preview is on or off — `uninstall()` keeps twins and re-adoption skips entities that
    /// have one, so a twin left behind would show the old payload or distance once the preview
    /// is back on: a twin whose payload did not change only takes the new options (no reload),
    /// a new payload relinks, no link unlinks. Only the creation of a twin waits for the
    /// preview to be on.
    static func applyPreview(entityId: EntityID) {
        let component = scene.get(component: GaussianAssetLinkComponent.self, for: entityId)
        guard let component, component.isMeshTwin, let payloadURL = component.payloadURL else {
            if hasComponent(entityId: entityId, componentType: GaussianTwinComponent.self) {
                removeEntityGaussianTwin(entityId: entityId)
            }
            return
        }
        let options = previewOptions(entityId: entityId, link: component)
        if let twin = scene.get(component: GaussianTwinComponent.self, for: entityId) {
            if twin.payloadURL?.standardizedFileURL == payloadURL.standardizedFileURL {
                twin.options = options
            } else {
                setEntityGaussianTwin(entityId: entityId, payloadURL: payloadURL, options: options)
            }
            return
        }
        guard previewEnabled() else { return }
        setEntityGaussianTwin(entityId: entityId, payloadURL: payloadURL, options: options)
    }

    // MARK: - File access

    private static func readFileData(at url: URL) throws -> Data {
        do {
            return try Data(contentsOf: url)
        } catch {
            throw GaussianTwinLinkError.readFailed(url, error.localizedDescription)
        }
    }

    static func readDecodedAsset(at url: URL) throws -> UntoldDecodedAsset {
        try decodeAsset(readFileData(at: url), at: url)
    }

    private static func decodeAsset(_ fileData: Data, at url: URL) throws -> UntoldDecodedAsset {
        do {
            return try UntoldReader().readAsset(from: fileData)
        } catch {
            throw GaussianTwinLinkError.readFailed(url, String(describing: error))
        }
    }

    private static func write(_ data: Data, to url: URL) throws {
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw GaussianTwinLinkError.writeFailed(url, error.localizedDescription)
        }
    }
}
