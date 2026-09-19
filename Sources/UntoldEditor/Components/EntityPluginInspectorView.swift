//
//  EntityPluginInspectorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import simd
import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// The entity's own block, when it is a kind of entity written in code (`EntityPlugin`): its
/// kind as the headline and a field for each of its properties. It comes before the
/// components because it is the entity, not something added to it, so it has no remove
/// button: deleting the entity is how it goes. The one exception is a kind whose type is no
/// longer loaded, which can be cleared so the entity can be kept as a plain one.
struct EntityPluginInspectorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @ObservedObject private var controller = ComponentLibraryController.shared

    static func isAvailable(for entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return false }
        return ScenePluginSystem.shared.entitySlot(on: entityId) != nil
    }

    /// Whether the entity's mesh was built by its own plugin (`setGeneratedMesh`). It is then
    /// part of the entity, and the Inspector does not remove it on its own.
    static func generatedMeshIsOwned(on entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents else { return false }
        return ScenePluginSystem.shared.entityPlugin(on: entityId)?.ownsGeneratedMesh ?? false
    }

    /// The headline and icon for the entity's kind: the loaded type's, or the saved type name
    /// when the library that defined it is not loaded.
    static func kind(of slot: ScenePluginSlotInfo) -> (title: String, systemImage: String) {
        guard let type = EntityPluginRegistry.shared.type(named: slot.typeName) else {
            return (slot.typeName, "questionmark.square.dashed")
        }
        return (type.displayName, type.systemImage)
    }

    var body: some View {
        if let slot = ScenePluginSystem.shared.entitySlot(on: entityId) {
            let kind = Self.kind(of: slot)
            VStack(alignment: .leading, spacing: 8) {
                PluginBlock(
                    entityId: entityId,
                    slot: slot,
                    instance: ScenePluginSystem.shared.entityPlugin(on: entityId),
                    title: kind.title,
                    badge: kind.systemImage,
                    badgeHelp: "This entity is a \(kind.title) (\(slot.typeName)), a kind of entity written in the project's code or one of its plugins. These are its own properties.",
                    removeHelp: "Forget that this entity was a \(slot.typeName), and its saved values. The entity stays.",
                    onRemove: slot.isBound ? nil : {
                        ScenePluginSystem.shared.removeEntityPlugin(from: entityId)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    },
                    refreshView: refreshView
                )
                Divider()
            }
            .id(controller.revision)
        }
    }
}
