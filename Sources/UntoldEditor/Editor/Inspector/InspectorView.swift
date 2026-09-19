//
//  InspectorView.swift
//
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

struct InspectorView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @ObservedObject var editorComponentsState = EditorComponentsState.shared
    var onAddName_Editor: () -> Void
    // @State private var editor_entityComponents: [EntityID: [ObjectIdentifier: ComponentOption_Editor]] = [:]
    @FocusState private var isNameTextFieldFocused: Bool
    @State private var nameEditStartValue: String?
    @Binding var selectedAsset: Asset?

    var body: some View {
        VStack(alignment: .leading) {
            if let entityId = selectionManager.selectedEntity, entityId != .invalid {
                ScrollView { // Make the entire inspector scrollable
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Name")
                            TextField("Set Entity Name", text: Binding(
                                get: { getEntityName(entityId: entityId) },
                                set: {
                                    setEntityName(entityId: entityId, name: $0)
                                }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding()
                            .focused($isNameTextFieldFocused)
                            .onSubmit {
                                if let oldName = nameEditStartValue {
                                    EditorUndoManager.shared.registerNameChange(
                                        entityId: entityId,
                                        oldName: oldName,
                                        newName: getEntityName(entityId: entityId)
                                    )
                                }
                                nameEditStartValue = nil
                                onAddName_Editor()
                                refreshView()
                                isNameTextFieldFocused = false
                            }
                            .onChange(of: isNameTextFieldFocused) { _, isFocused in
                                if isFocused {
                                    nameEditStartValue = getEntityName(entityId: entityId)
                                } else if let oldName = nameEditStartValue {
                                    EditorUndoManager.shared.registerNameChange(
                                        entityId: entityId,
                                        oldName: oldName,
                                        newName: getEntityName(entityId: entityId)
                                    )
                                    nameEditStartValue = nil
                                    refreshView()
                                }
                            }
                        }

                        if isDerivedAssetNode(entityId) {
                            AssetNodeInspectorBanner(entityId: entityId, selectionManager: selectionManager)
                        }

                        // The entity's own properties, when it is a kind of entity written in code
                        // (EntityPlugin). They are the entity, so they come before its components.
                        if EntityPluginInspectorView.isAvailable(for: entityId) {
                            EntityPluginInspectorView(entityId: entityId, refreshView: refreshView)
                                .frame(minWidth: 200, maxWidth: 250)
                                .id(entityId)
                        }

                        if hasComponent(entityId: entityId, componentType: TileComponent.self) {
                            TileMeshListInspectorView(entityId: entityId)
                            Divider()
                        }

                        if let inspectedMesh = selectionManager.inspectedMesh,
                           inspectedMesh.entityId == entityId
                        {
                            // inspectMesh() (see SelectionManager) only ever sets inspectedMesh
                            // alongside selectedEntity on the same entity, so reaching this
                            // block means entityId genuinely is the active selection, not just
                            // a passive peek — safe (and expected) to be fully editable here.
                            RenderingEditorView(
                                entityId: entityId,
                                asset: selectedAsset,
                                refreshView: refreshView,
                                meshIndex: inspectedMesh.meshIndex,
                                inspectionOnly: false
                            )
                            Divider()
                        }

                        if let entityId = selectionManager.selectedEntity {
                            let mergedComponents = mergeEntityComponents(
                                selectedEntity: entityId,
                                editor_availableComponents: availableComponents_Editor
                            )

                            // The inspectedMesh banner above already renders this entity's
                            // Render Component (with the correct submesh index) when it targets
                            // this same entity. Skip the generic entry here so Material
                            // Properties / Wrap Mode don't render twice.
                            let isInspectedMeshEntity = selectionManager.inspectedMesh?.entityId == entityId
                            let visibleComponents = visibleInspectorComponents(
                                mergedComponents: mergedComponents,
                                entityId: entityId,
                                isInspectedMeshEntity: isInspectedMeshEntity
                            )

                            let sortedComponents = sortEntityComponents(componentOption_Editor: visibleComponents)

                            // Static Batching Section - Show for any entity with renderable hierarchy
                            if EditorAuthoringMode.sceneCompositionOnly == false, isDerivedAssetNode(entityId) == false {
                                StaticBatchingEditorView(entityId: entityId, refreshView: refreshView)
                            }

                            ForEach(sortedComponents, id: \.id) { editor_component in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(editor_component.name)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if canRemoveComponentFromInspector(componentType: editor_component.type, from: entityId) {
                                            Button(action: {
                                                removeComponentFromEntity_Editor(componentType: editor_component.type)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.editorError)
                                            }
                                            .buttonStyle(BorderlessButtonStyle())
                                        }
                                    }

                                    editor_component.view(entityId, selectedAsset, refreshView)
                                        .frame(minWidth: 200, maxWidth: 250)
                                }
                                Divider()
                            }

                            // Component plugins written in the project's Swift sources and loaded by
                            // the editor, one block each like the engine's above. An ad-hoc section
                            // (not a ComponentOption_Editor) so scene-composition mode, which whitelists
                            // registered components, keeps it.
                            if ScenePluginInspectorView.isAvailable(for: entityId) {
                                ScenePluginInspectorView(entityId: entityId, refreshView: refreshView)
                                    .frame(minWidth: 200, maxWidth: 250)
                                    .id(entityId)
                            }

                            // One menu for everything that can be added: the engine's components
                            // and the ones the loaded code defines.
                            AddComponentMenu(
                                entityId: entityId,
                                engineComponents: availableComponentsWithFlags(),
                                addEngineComponent: { addComponentToEntity_Editor(componentType: $0) },
                                refreshView: refreshView
                            )

                        } else {
                            Text("No entity selected").foregroundColor(.editorTextTertiary)
                        }
                    }
                }
                .frame(maxHeight: .infinity) // Ensure ScrollView takes available space

            } else {
                Text("No entity selected")
                    .foregroundColor(.editorTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/*
 struct TemplateEditorView: View{
 let entityId: EntityID
 let asset: Asset?
 let refreshView: () -> Void

 var body: some View{

 }
 }
 */
