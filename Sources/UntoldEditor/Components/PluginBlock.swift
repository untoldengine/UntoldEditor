//
//  PluginBlock.swift
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

// MARK: - One plugin

/// One block of fields: the headline, then a field per attribute and a button per action, or
/// a note when the type is not loaded. Shared by the entity's own block and its components.
struct PluginBlock: View {
    let entityId: EntityID
    let slot: ScenePluginSlotInfo
    let instance: ScenePlugin?
    /// The headline; `nil` takes the plugin's display name.
    let title: String?
    let badge: String
    let badgeHelp: String
    let removeHelp: String
    /// `nil` when the block cannot be removed.
    let onRemove: (() -> Void)?
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title ?? instance.map { type(of: $0).displayName } ?? slot.typeName)
                    .font(.headline)
                Image(systemName: badge)
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextTertiary)
                    .help(badgeHelp)
                Spacer()
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash").foregroundColor(.editorError)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help(removeHelp)
                }
            }

            if let instance {
                ForEach(instance.untoldAttributes(), id: \.name) { entry in
                    AttributeField(entry: entry) { newValue in
                        write(newValue, to: entry)
                    }
                }
                let actions = type(of: instance).actions
                if actions.isEmpty == false {
                    HStack(spacing: 6) {
                        ForEach(actions, id: \.name) { action in
                            Button(action.name) {
                                ScenePluginSystem.shared.performAction(action.name, of: slot.typeName, on: entityId)
                                refreshView()
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                Text("Not available in the loaded library. Its \(slot.payload.count) saved value\(slot.payload.count == 1 ? " is" : "s are") kept.")
                    .font(.caption)
                    .foregroundColor(.editorWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func write(_ newValue: UntoldAttributeValue, to entry: UntoldAttributeEntry) {
        let oldValue = entry.attribute.attributeValue
        guard oldValue != newValue else { return }
        let entity = entityId
        let typeName = slot.typeName
        let property = entry.name
        guard ScenePluginSystem.shared.setAttribute(property, of: typeName, on: entity, to: newValue) else { return }

        EditorSceneDirtyState.shared.markDirty()
        EditorUndoManager.shared.registerValueChange(
            name: "Change \(entry.displayLabel)",
            oldValue: oldValue,
            newValue: newValue
        ) { restored in
            ScenePluginSystem.shared.setAttribute(property, of: typeName, on: entity, to: restored)
            EditorSceneDirtyState.shared.markDirty()
            editorController?.refreshInspector()
        }
        refreshView()
    }
}
