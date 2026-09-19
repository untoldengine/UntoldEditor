//
//  EditorView+DragDrop.swift
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
    // MARK: - Asset drag-and-drop

    /// Viewport drop: the entity lands where the cursor's ray meets the ground plane,
    /// or at the origin when the ray misses it (looking at the sky, say).
    func editor_dropAssetOnViewport(providers: [NSItemProvider], location: CGPoint) -> Bool {
        let viewportSize = renderer?.metalView.bounds.size ?? .zero
        return loadDroppedRowPayload(from: providers) { payload in
            let position = sceneCameraGroundPlaneHit(atViewportLocation: location, viewportSize: viewportSize)
            editor_placeDroppedRow(payload, parent: nil, at: position)
        }
    }

    /// Places whatever a dropped row carries. One place for the hierarchy drop and the
    /// viewport drop, and out of `body`, which is at the type checker's limit.
    func editor_placeDroppedRow(_ payload: DroppedRowPayload, parent: EntityID?, at position: simd_float3? = nil) {
        switch payload {
        case let .asset(assetPayload):
            editor_placeDroppedAsset(assetPayload, parent: parent, at: position)
        case let .light(lightPayload):
            editor_placeDroppedLight(lightPayload, parent: parent, at: position)
        case let .primitive(primitivePayload):
            editor_placeDroppedPrimitive(primitivePayload, parent: parent, at: position)
        case let .entityPlugin(pluginPayload):
            editor_placeDroppedEntityPlugin(pluginPayload, parent: parent, at: position)
        }
    }

    /// Places a dropped entity template row (a kind of entity that loaded code added),
    /// parenting it under `parent` for a hierarchy drop, same as `editor_placeDroppedAsset`.
    func editor_placeDroppedEntityPlugin(_ payload: EntityPluginDragPayload, parent: EntityID?, at position: simd_float3? = nil) {
        guard let placement = placeEntityPlugin(
            payload.entityPlugin,
            at: position,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        ) else {
            showDropStatus("'\(payload.entityPlugin)' is no longer loaded.", isError: true)
            return
        }
        if let parent {
            editor_parentEntity(childId: placement.entityId, parentId: parent)
        }
        editor_entities = getAllGameEntities()
        showDropStatus(placement.statusMessage, isError: placement.isError)
    }

    /// Places a dropped asset browser row, parenting it under `parent` for a
    /// hierarchy drop. Unsupported kinds only show a status message.
    func editor_placeDroppedAsset(_ payload: AssetDragPayload, parent: EntityID?, at position: simd_float3? = nil) {
        let asset = payload.asset
        guard let placeable = placeableAsset(for: asset) else {
            showDropStatus(unsupportedAssetDropMessage(for: asset), isError: true)
            return
        }

        let placement = placeAsset(
            placeable,
            at: position,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        )
        if let parent {
            editor_parentEntity(childId: placement.entityId, parentId: parent)
        }
        editor_entities = getAllGameEntities()
        showDropStatus(placement.statusMessage, isError: placement.isError)
    }

    /// Places a dropped Lights shelf row, parenting it under `parent` for a
    /// hierarchy drop, same as `editor_placeDroppedAsset`.
    func editor_placeDroppedLight(_ payload: LightDragPayload, parent: EntityID?, at position: simd_float3? = nil) {
        let placement = placeLight(
            payload.lightType,
            at: position,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        )
        if let parent {
            editor_parentEntity(childId: placement.entityId, parentId: parent)
        }
        editor_entities = getAllGameEntities()
        showDropStatus(placement.statusMessage, isError: placement.isError)
    }

    /// Places a dropped Primitives shelf row, parenting it under `parent` for a
    /// hierarchy drop, same as `editor_placeDroppedAsset`.
    func editor_placeDroppedPrimitive(_ payload: PrimitiveDragPayload, parent: EntityID?, at position: simd_float3? = nil) {
        let placement = placePrimitive(
            payload.primitiveType,
            at: position,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        )
        if let parent {
            editor_parentEntity(childId: placement.entityId, parentId: parent)
        }
        editor_entities = getAllGameEntities()
        showDropStatus(placement.statusMessage, isError: placement.isError)
    }

    func showDropStatus(_ message: String, isError: Bool = false) {
        withAnimation {
            dropStatusMessage = message
            dropStatusIsError = isError
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if dropStatusMessage == message {
                withAnimation {
                    dropStatusMessage = nil
                }
            }
        }
    }
}
