//
//  ScenePluginInspectorView.swift
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

/// The component plugins the entity carries, shown in the Inspector the way the engine's
/// components are: one block each, a headline with a remove button, then a field for every
/// `@UntoldAttribute` and a button for every action. They are added from the Inspector's one
/// Add Component menu (`AddComponentMenu`), alongside the engine's.
///
/// Drawn by the Inspector directly rather than registered as component options, because the
/// set of types changes whenever a library loads, and so scene-composition mode keeps them.
struct ScenePluginInspectorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @ObservedObject private var controller = ComponentLibraryController.shared

    /// Whether the Inspector has any component plugin to draw for `entityId`.
    static func isAvailable(for entityId: EntityID) -> Bool {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return false }
        return ScenePluginSystem.shared.slots(on: entityId).isEmpty == false
    }

    /// The loaded component plugins `entityId` does not carry yet, for the Add Component menu.
    /// Every one of them: a component is something any entity can have. What belongs to one
    /// kind of entity only is a property of its `EntityPlugin`, and is never in this list.
    static func addableTypes(for entityId: EntityID) -> [ComponentPluginRegistry.Entry] {
        guard EditorFeatureFlags.enableCodeComponents, isDerivedAssetNode(entityId) == false else { return [] }
        let present = Set(ScenePluginSystem.shared.slots(on: entityId).map(\.typeName))
        return ComponentPluginRegistry.shared.entries
            .filter { present.contains($0.name) == false }
            .sorted { $0.type.displayName < $1.type.displayName }
    }

    /// Adds a component by type name, as the Add Component menu does.
    static func add(_ typeName: String, to entityId: EntityID) {
        ScenePluginSystem.shared.add(typeName, to: entityId)
        EditorSceneDirtyState.shared.markDirty()
    }

    var body: some View {
        let slots = ScenePluginSystem.shared.slots(on: entityId)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(slots, id: \.typeName) { slot in
                PluginBlock(
                    entityId: entityId,
                    slot: slot,
                    instance: ScenePluginSystem.shared.component(named: slot.typeName, on: entityId),
                    title: nil,
                    badge: "swift",
                    badgeHelp: "\(slot.typeName), a component written in the project's code or one of its plugins",
                    removeHelp: "Remove \(slot.typeName) and its saved values",
                    onRemove: {
                        ScenePluginSystem.shared.remove(slot.typeName, from: entityId)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    },
                    refreshView: refreshView
                )
                Divider()
            }
        }
        // A new library revision swaps every instance: rebuild the fields against the new ones.
        .id(controller.revision)
    }
}
