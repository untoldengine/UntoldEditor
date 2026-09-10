//
//  GaussianTwinInspectorModel.swift
//  UntoldEditor
//
//  State behind the Inspector's Splat Twin section, kept apart from the SwiftUI view so the
//  assign / edit / remove flow, its debounced persistence and its undo registration can be
//  exercised without a window.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import simd
import UntoldEngine
import UntoldGaussianTwins

/// Cancels an action scheduled through a `GaussianTwinPersistScheduler`.
typealias GaussianTwinPersistCancel = () -> Void
/// Runs `action` after `delay`; returns a cancel. The live model uses the main queue, tests
/// capture the action and run it by hand.
typealias GaussianTwinPersistScheduler = (_ delay: TimeInterval, _ action: @escaping () -> Void) -> GaussianTwinPersistCancel

/// Policy of the Splat Twin section: which entities get one, what the browser selection can
/// assign, and the ranges the fields accept.
enum GaussianTwinInspector {
    /// The section is shown for mesh entities placed from a `.untold` file: the root of a
    /// single-node asset or a bindable mesh node of a multi-node one. Lights, cameras,
    /// transform-only nodes, primitives, splats, multi-node roots (no mesh of their own) and
    /// streamed stubs (their node paths are the streamer's, not the file's) get none. Cheap —
    /// it does not read the file; the model reports a file that cannot be mapped to an entity
    /// record in its status line.
    static func isAvailable(_ entityId: EntityID) -> Bool {
        guard entityId != .invalid,
              hasComponent(entityId: entityId, componentType: RenderComponent.self),
              !hasComponent(entityId: entityId, componentType: StreamingComponent.self),
              !hasComponent(entityId: entityId, componentType: CameraComponent.self),
              !hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self),
              !hasComponent(entityId: entityId, componentType: PointLightComponent.self),
              !hasComponent(entityId: entityId, componentType: SpotLightComponent.self),
              !hasComponent(entityId: entityId, componentType: AreaLightComponent.self)
        else { return false }
        if isDerivedAssetNode(entityId), isBindableAssetMeshNode(entityId) == false {
            return false
        }
        return GaussianTwinLinkPersistence.resolveUntoldURL(entityId: entityId) != nil
    }

    /// The payload the browser's selected asset stands for: a `.untoldgs` file in the
    /// Gaussians category. `.ply` sources must be cooked first.
    static func assignablePayloadURL(from asset: Asset?) -> URL? {
        guard let asset,
              asset.isFolder == false,
              asset.category == AssetCategory.gaussians.rawValue,
              asset.path.pathExtension.lowercased() == "untoldgs"
        else { return nil }
        return asset.path
    }

    static let exposureOffsetRange: ClosedRange<Float> = -4 ... 4

    /// Distances are metres, never negative (0 = swap at any distance); the exposure offset is
    /// clamped to ±4 EV. Non-finite input keeps the previous value.
    static func clampedSwapDistance(_ value: Float, previous: Float) -> Float {
        value.isFinite ? max(0, value) : previous
    }

    static func clampedOccluderShrink(_ value: Float, previous: Float) -> Float {
        value.isFinite ? max(0, value) : previous
    }

    static func clampedExposureOffset(_ value: Float, previous: Float) -> Float {
        value.isFinite ? min(max(value, exposureOffsetRange.lowerBound), exposureOffsetRange.upperBound) : previous
    }

    /// The live scheduler: the main queue.
    static let mainQueueScheduler: GaussianTwinPersistScheduler = { delay, action in
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return { item.cancel() }
    }

    /// Human-readable twin state for the section's preview line.
    static func stateTitle(_ state: GaussianTwinState) -> String {
        switch state {
        case .armed: return "armed"
        case .loading: return "loading"
        case .crossFading: return "cross-fading"
        case .swapped: return "swapped"
        case .reverting: return "reverting"
        }
    }
}

/// One entity's Splat Twin section. Edits apply to the live scene at once (link component and
/// viewport preview); the `.untold` file is written immediately on assign and remove, and
/// `persistDelay` after the last field edit. Every change registers an undo step carrying the
/// whole link before and after.
final class GaussianTwinInspectorModel: ObservableObject {
    struct Status: Equatable {
        var message: String
        var isError: Bool
    }

    static let persistDelay: TimeInterval = 0.4
    static let noTwinTitle = "No twin"

    let entityId: EntityID
    /// Where the link is stored; nil when the entity cannot be mapped to a `.untold` record
    /// (`status` says why).
    @Published private(set) var target: GaussianTwinLinkTarget?
    /// The link as edited — ahead of the file while a persist is pending.
    @Published private(set) var link: UntoldAssetPatcher.GaussianAssetLink?
    @Published private(set) var status: Status?
    @Published private(set) var hasPendingPersist = false

    private let scheduler: GaussianTwinPersistScheduler
    private let undoManager: EditorUndoManager
    private var cancelPendingPersist: GaussianTwinPersistCancel?
    private var changeObserver: NSObjectProtocol?
    /// The target's decoded file, kept so live edits can find the other placements of the
    /// record without reading it again; refreshed by `reload()`.
    private var decoded: UntoldDecodedAsset?

    init(
        entityId: EntityID,
        scheduler: @escaping GaussianTwinPersistScheduler = GaussianTwinInspector.mainQueueScheduler,
        undoManager: EditorUndoManager = .shared
    ) {
        self.entityId = entityId
        self.scheduler = scheduler
        self.undoManager = undoManager
        reload()
        // Delivered on the posting thread (always main here), so a write made through the
        // undo stack is reflected before the caller returns. The model's own writes name it as
        // the object and are skipped: `link` already says what was written.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .gaussianTwinLinkDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  (notification.object as AnyObject?) !== self,
                  let changed = notification.userInfo?[GaussianTwinLinkPersistence.targetUserInfoKey] as? GaussianTwinLinkTarget,
                  changed == target
            else { return }
            linkDidChangeOnDisk()
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
        flushPendingPersist()
    }

    // MARK: - Reading

    /// Resolves the target and reads the link from the file (one read, one decode). Clears
    /// the status.
    func reload() {
        do {
            let loaded = try GaussianTwinLinkPersistence.loadTarget(entityId: entityId)
            target = loaded.target
            decoded = loaded.decoded
            link = try GaussianTwinLinkPersistence.readTwinLink(target: loaded.target, decoded: loaded.decoded)
            status = nil
        } catch {
            target = nil
            decoded = nil
            link = nil
            status = Status(message: error.localizedDescription, isError: true)
        }
    }

    /// The stored payload path, or `noTwinTitle`.
    var payloadDisplay: String {
        link?.payloadPath ?? Self.noTwinTitle
    }

    /// Where the payload is loaded from, for the tooltip.
    var payloadURL: URL? {
        guard let link, let target else { return nil }
        return GaussianTwinLinkPersistence.resolvedPayloadURL(path: link.payloadPath, untoldURL: target.untoldURL)
    }

    var swapDistance: Float {
        link?.swapDistanceMeters ?? 0
    }

    var occluderShrink: Float {
        link?.occluderShrinkMeters ?? 0.02
    }

    var exposureOffset: Float {
        link?.exposureOffsetEV ?? 0
    }

    // MARK: - Assign / remove (persisted at once)

    func assignSelectedAsset(_ asset: Asset?) {
        guard let url = GaussianTwinInspector.assignablePayloadURL(from: asset) else {
            status = Status(message: "Select a .untoldgs file in the Asset Browser's Gaussians folder, then assign it here.", isError: true)
            return
        }
        assign(payloadURL: url)
    }

    /// Links `payloadURL` (a version 3 `.untoldgs`), keeping the current settings when a link
    /// already exists, and writes the file.
    func assign(payloadURL: URL) {
        guard let target else {
            reload()
            guard target != nil else { return }
            assign(payloadURL: payloadURL)
            return
        }
        let previous = link
        do {
            let stored = GaussianTwinLinkPersistence.storedPayloadPath(payloadURL: payloadURL, untoldURL: target.untoldURL)
            let newLink = try GaussianTwinLinkPersistence.makeLink(
                payloadURL: payloadURL,
                untoldURL: target.untoldURL,
                swapDistanceMeters: previous?.swapDistanceMeters ?? 0,
                occluderShrinkMeters: previous?.occluderShrinkMeters ?? 0.02,
                exposureOffsetEV: previous?.exposureOffsetEV ?? 0
            )
            cancelScheduledPersist()
            try GaussianTwinLinkPersistence.writeTwinLink(target: target, link: newLink, writer: self)
            link = newLink
            registerUndo(name: "Assign Splat Twin", from: previous, to: newLink)
            let splats = newLink.lodSplatCounts.first ?? 0
            var message = "Linked \(payloadURL.lastPathComponent) (\(splats.formatted()) splats)."
            if stored.isRelative == false {
                message += " Stored by file name only (another volume): keep it next to \(target.untoldURL.lastPathComponent)."
            }
            status = Status(message: message, isError: false)
        } catch {
            status = Status(message: error.localizedDescription, isError: true)
        }
    }

    /// Drops the link from the file, the scene and the preview.
    func removeLink() {
        guard let target, let previous = link else { return }
        cancelScheduledPersist()
        do {
            try GaussianTwinLinkPersistence.removeTwinLink(target: target, writer: self)
            link = nil
            registerUndo(name: "Remove Splat Twin", from: previous, to: nil)
            status = nil
        } catch {
            status = Status(message: error.localizedDescription, isError: true)
        }
    }

    // MARK: - Fields (live, persisted after a pause)

    func setSwapDistance(_ value: Float) {
        updateLink(name: "Splat Twin Swap Distance") { link in
            link.swapDistanceMeters = GaussianTwinInspector.clampedSwapDistance(value, previous: link.swapDistanceMeters)
        }
    }

    func setOccluderShrink(_ value: Float) {
        updateLink(name: "Splat Twin Occluder Shrink") { link in
            link.occluderShrinkMeters = GaussianTwinInspector.clampedOccluderShrink(value, previous: link.occluderShrinkMeters)
        }
    }

    func setExposureOffset(_ value: Float) {
        updateLink(name: "Splat Twin Exposure Offset") { link in
            link.exposureOffsetEV = GaussianTwinInspector.clampedExposureOffset(value, previous: link.exposureOffsetEV)
        }
    }

    private func updateLink(name: String, _ mutate: (inout UntoldAssetPatcher.GaussianAssetLink) -> Void) {
        guard let target, let previous = link else { return }
        var updated = previous
        mutate(&updated)
        guard updated != previous else { return }
        link = updated
        applyLive(updated, target: target)
        schedulePersist()
        registerUndo(name: name, from: previous, to: updated)
    }

    /// Mirrors an edited link onto the scene without touching the file.
    private func applyLive(_ link: UntoldAssetPatcher.GaussianAssetLink, target: GaussianTwinLinkTarget) {
        for backed in backedEntities(target) {
            GaussianTwinLinkPersistence.applyLinkComponent(link, to: backed, untoldURL: target.untoldURL)
            GaussianTwinLinkPersistence.applyPreview(entityId: backed)
        }
    }

    private func backedEntities(_ target: GaussianTwinLinkTarget) -> [EntityID] {
        if let decoded {
            return GaussianTwinLinkPersistence.entitiesBacked(by: target, decoded: decoded)
        }
        return GaussianTwinLinkPersistence.entitiesBacked(by: target)
    }

    // MARK: - Persistence

    private func schedulePersist() {
        cancelScheduledPersist()
        hasPendingPersist = true
        cancelPendingPersist = scheduler(Self.persistDelay) { [weak self] in
            self?.flushPendingPersist()
        }
    }

    private func cancelScheduledPersist() {
        cancelPendingPersist?()
        cancelPendingPersist = nil
        hasPendingPersist = false
    }

    /// Writes the edited link now if a write is pending (the debounce fired, the section is
    /// leaving the screen, the model is going away). When the write fails the scene and the
    /// model snap back to what the file holds — the live edit would otherwise outlive the
    /// session it was made in — and the failure is logged, since the section may be gone by
    /// the time it is known.
    func flushPendingPersist() {
        guard hasPendingPersist else { return }
        cancelScheduledPersist()
        guard let target, let link else { return }
        do {
            try GaussianTwinLinkPersistence.writeTwinLink(target: target, link: link, writer: self)
        } catch {
            Logger.logWarning(message: "[GaussianTwinInspector] Could not persist the twin link of \(target.untoldURL.lastPathComponent): \(error.localizedDescription)")
            status = Status(message: error.localizedDescription, isError: true)
            revertToFile(target: target)
        }
    }

    /// Puts the model and the scene back on the persisted record. Leaves both alone when the
    /// file cannot be read either: there is nothing to snap back to.
    private func revertToFile(target: GaussianTwinLinkTarget) {
        let persisted: UntoldAssetPatcher.GaussianAssetLink?
        do {
            persisted = try GaussianTwinLinkPersistence.readTwinLink(target: target)
        } catch {
            return
        }
        link = persisted
        GaussianTwinLinkPersistence.applyToScene(target: target, link: persisted, decoded: decoded, writer: self)
    }

    /// Another writer (undo, a second inspector of the same asset) changed the record: drop
    /// what was pending here and show what the file says.
    private func linkDidChangeOnDisk() {
        guard let target else { return }
        cancelScheduledPersist()
        if let fresh = try? GaussianTwinLinkPersistence.readTwinLink(target: target) {
            link = fresh
        } else {
            link = nil
        }
    }

    // MARK: - Undo

    private func registerUndo(
        name: String,
        from oldValue: UntoldAssetPatcher.GaussianAssetLink?,
        to newValue: UntoldAssetPatcher.GaussianAssetLink?
    ) {
        guard let target else { return }
        undoManager.registerValueChange(name: name, oldValue: oldValue, newValue: newValue) { restored in
            do {
                try GaussianTwinLinkPersistence.restoreTwinLink(target: target, link: restored)
            } catch {
                Logger.logWarning(message: "[GaussianTwinInspector] Undo could not restore the twin link of \(target.untoldURL.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Preview state

    /// "swapped · 3.2 m" while the preview runs a twin on this entity; nil without one.
    func liveTwinDescription() -> String? {
        guard let twin = scene.get(component: GaussianTwinComponent.self, for: entityId) else { return nil }
        var parts = [GaussianTwinInspector.stateTitle(twin.state)]
        if twin.state == .crossFading || twin.state == .reverting {
            parts[0] += " \(Int((twin.fadeProgress * 100).rounded()))%"
        }
        if twin.loadFailed {
            parts.append("payload failed to load")
        }
        if let distance = distanceToActiveCamera() {
            parts.append(String(format: "%.1f m", distance))
        }
        return parts.joined(separator: " · ")
    }

    /// Camera distance to the entity's bounds centre, as `GaussianTwinSystem` measures it.
    private func distanceToActiveCamera() -> Float? {
        guard let camera = CameraSystem.shared.activeCamera,
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera),
              let worldTransform = scene.get(component: WorldTransformComponent.self, for: entityId),
              let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId)
        else { return nil }
        let cameraPosition = SceneRootTransform.shared.effectiveCameraPosition(cameraComponent.localPosition)
        let box = localTransform.boundingBox
        let localCenter = (box.min + box.max) * 0.5
        let worldCenter = worldTransform.space * simd_float4(localCenter, 1)
        return simd_distance(cameraPosition, simd_float3(worldCenter.x, worldCenter.y, worldCenter.z))
    }
}
