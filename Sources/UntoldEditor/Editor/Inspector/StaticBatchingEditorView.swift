//
//  StaticBatchingEditorView.swift
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
import UniformTypeIdentifiers
import UntoldEngine

// MARK: - Static Batching Section

struct StaticBatchingEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @State private var staticBatchCheckboxState: Bool = false

    /// Check if entity or any of its children have RenderComponent
    private func hasRenderableHierarchy(entityId: EntityID) -> Bool {
        // Check self
        if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
            return true
        }

        // Check children recursively
        let children = getEntityChildren(parentId: entityId)
        for child in children {
            if hasRenderableHierarchy(entityId: child) {
                return true
            }
        }

        return false
    }

    /// Check if entity or any of its children have StaticBatchComponent
    private func isMarkedAsStatic(entityId: EntityID) -> Bool {
        // Check self
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            return true
        }

        // Check children recursively
        let children = getEntityChildren(parentId: entityId)
        for child in children {
            if isMarkedAsStatic(entityId: child) {
                return true
            }
        }

        return false
    }

    var body: some View {
        // Only show if entity or children have RenderComponent (but not lights)
        if hasRenderableHierarchy(entityId: entityId), hasComponent(entityId: entityId, componentType: LightComponent.self) == false {
            VStack(alignment: .leading, spacing: 4) {
                Text("Static Batching")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let hasOwnRenderComponent = hasComponent(entityId: entityId, componentType: RenderComponent.self)
                let labelText = hasOwnRenderComponent ? "Mark as Static" : "Mark Children as Static"
                let helpText = hasOwnRenderComponent
                    ? "Enable static batching for this entity (combines geometry to reduce draw calls)"
                    : "Enable static batching for all children of this entity (combines geometry to reduce draw calls)"

                HStack {
                    Image(systemName: "square.3.layers.3d")
                        .foregroundColor(.editorInfo)
                    Text(labelText)
                        .font(.callout)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { staticBatchCheckboxState },
                        set: { isStatic in
                            if isStatic {
                                setEntityStaticBatchComponent(entityId: entityId)
                            } else {
                                removeEntityStaticBatchComponent(entityId: entityId)
                            }
                            staticBatchCheckboxState = isStatic
                            refreshView()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.editorAccent)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.editorFillSubtle)
                .cornerRadius(8)
                .help(helpText)
                .onAppear {
                    // Update checkbox state when view appears
                    staticBatchCheckboxState = isMarkedAsStatic(entityId: entityId)
                }
                .onChange(of: entityId) { newEntityId in
                    // Update checkbox state when entity selection changes
                    staticBatchCheckboxState = isMarkedAsStatic(entityId: newEntityId)
                }
            }

            Divider()
        }
    }
}
