//
//  EntityTemplatePlacement.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import CoreTransferable
import Foundation
import simd
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

/// What a shelf row for an entity template puts on the drag pasteboard: the template's
/// type name. It travels as `.json` like the other row payloads, and its one required
/// field is unlike theirs, so `loadDroppedRowPayload` can tell it apart.
struct EntityTemplateDragPayload: Codable, Equatable, Transferable {
    static let contentType: UTType = .json

    var entityTemplate: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> EntityTemplateDragPayload {
        try JSONDecoder().decode(EntityTemplateDragPayload.self, from: data)
    }
}

/// One row of a creation shelf that loaded code contributed.
struct EntityTemplateShelfItem: Identifiable, Equatable {
    let typeName: String
    let displayName: String
    let systemImage: String

    var id: String {
        typeName
    }

    static func items(on shelf: UntoldEntityShelf) -> [EntityTemplateShelfItem] {
        EntityTemplateRegistry.shared.entries(on: shelf).map {
            EntityTemplateShelfItem(typeName: $0.name, displayName: $0.type.displayName, systemImage: $0.type.systemImage)
        }
    }
}

/// Creates an entity from the template named `typeName`, mirroring `placePrimitive`. The
/// template may have been unloaded between the drag and the drop; then nothing is created
/// and the status message says so.
@discardableResult
func placeEntityTemplate(
    _ typeName: String,
    at position: simd_float3? = nil,
    sceneGraphModel: SceneGraphModel,
    selectionManager: SelectionManager
) -> AssetPlacementResult? {
    guard let type = EntityTemplateRegistry.shared.type(named: typeName) else {
        Logger.logWarning(message: "[Components] Entity template '\(typeName)' is not loaded; nothing was created.")
        return nil
    }
    let uniqueName = generateEntityName()
    guard let entityId = EntityTemplateRegistry.shared.instantiate(typeName, at: position, entityName: uniqueName) else {
        return nil
    }
    EditorSceneDirtyState.shared.markDirty()

    selectionManager.selectedEntity = entityId
    sceneGraphModel.refreshHierarchy()

    return AssetPlacementResult(
        entityId: entityId,
        entityName: uniqueName,
        statusMessage: "Added \(type.displayName): \(uniqueName)"
    )
}
