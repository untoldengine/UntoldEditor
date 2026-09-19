//
//  InspectorView.swift
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

/// The Inspector: the entity's header, then one section per component with
/// its editor, then Add Component. With nothing to show, the empty state.
struct InspectorView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @ObservedObject var editorComponentsState = EditorComponentsState.shared
    @ObservedObject var clipboard = EditorComponentClipboard.shared
    var onAddName_Editor: () -> Void
    @Binding var selectedAsset: Asset?

    /// The entity the Inspector shows: the pinned one while it is in the scene,
    /// otherwise the selection.
    var inspectedEntity: EntityID? {
        if let pinned = selectionManager.pinnedInspection, sceneGraphModel.contains(pinned) {
            return pinned
        }
        guard let selected = selectionManager.selectedEntity, selected != .invalid else {
            return nil
        }
        return selected
    }

    var body: some View {
        Group {
            if let entityId = inspectedEntity {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        InspectorEntityHeader(entityId: entityId, selectionManager: selectionManager) {
                            onAddName_Editor()
                            refreshView()
                        }
                        Color.editorHairline.frame(height: 1)

                        if isDerivedAssetNode(entityId) {
                            AssetNodeInspectorBanner(entityId: entityId, selectionManager: selectionManager)
                                .padding(10)
                        }

                        // The entity's own properties, when it is a kind of entity written in code
                        // (EntityPlugin). They are the entity, so they come before its components.
                        if EntityPluginInspectorView.isAvailable(for: entityId) {
                            EntityPluginInspectorView(entityId: entityId, refreshView: refreshView)
                                .padding(.horizontal, 10)
                                .id(entityId)
                        }

                        if hasComponent(entityId: entityId, componentType: TileComponent.self) {
                            InspectorSectionView(title: "Tiles") {
                                TileMeshListInspectorView(entityId: entityId)
                            }
                        }

                        if let inspectedMesh = selectionManager.inspectedMesh,
                           inspectedMesh.entityId == entityId
                        {
                            // inspectMesh() (see SelectionManager) only ever sets inspectedMesh
                            // alongside selectedEntity on the same entity, so reaching this
                            // block means entityId genuinely is the active selection, not just
                            // a passive peek — safe (and expected) to be fully editable here.
                            InspectorSectionView(
                                title: "Mesh Renderer",
                                onCopy: { clipboard.copyMaterial(of: entityId, meshIndex: inspectedMesh.meshIndex) },
                                onPaste: {
                                    clipboard.pasteMaterial(into: entityId, meshIndex: inspectedMesh.meshIndex)
                                    refreshView()
                                },
                                canPaste: clipboard.material != nil
                            ) {
                                RenderingEditorView(
                                    entityId: entityId,
                                    asset: selectedAsset,
                                    refreshView: refreshView,
                                    meshIndex: inspectedMesh.meshIndex,
                                    inspectionOnly: false
                                )
                            }
                        }

                        componentSections(for: entityId)

                        // Component plugins written in the project's Swift sources and loaded by
                        // the editor, one block each like the engine's above. An ad-hoc section
                        // (not a ComponentOption_Editor) so scene-composition mode, which whitelists
                        // registered components, keeps it.
                        if ScenePluginInspectorView.isAvailable(for: entityId) {
                            ScenePluginInspectorView(entityId: entityId, refreshView: refreshView)
                                .padding(.horizontal, 10)
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
                        .padding(10)
                    }
                }
            } else {
                InspectorEmptyStateView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.editorPanelBackground)
    }

    private func componentSections(for entityId: EntityID) -> some View {
        let mergedComponents = mergeEntityComponents(
            selectedEntity: entityId,
            editor_availableComponents: availableComponents_Editor
        )
        // The inspected-mesh section above already shows this entity's Render
        // Component with the right submesh; the generic one would repeat it.
        let isInspectedMeshEntity = selectionManager.inspectedMesh?.entityId == entityId
        let visibleComponents = visibleInspectorComponents(
            mergedComponents: mergedComponents,
            entityId: entityId,
            isInspectedMeshEntity: isInspectedMeshEntity
        )
        let sortedComponents = sortEntityComponents(componentOption_Editor: visibleComponents)

        return VStack(alignment: .leading, spacing: 0) {
            // Static batching: any entity with a renderable hierarchy, outside composition mode.
            if EditorAuthoringMode.sceneCompositionOnly == false, isDerivedAssetNode(entityId) == false {
                InspectorSectionView(title: "Static Batching") {
                    StaticBatchingEditorView(entityId: entityId, refreshView: refreshView)
                }
            }

            ForEach(sortedComponents, id: \.id) { component in
                componentSection(component, entityId: entityId)
            }
        }
    }

    private func componentSection(_ component: ComponentOption_Editor, entityId: EntityID) -> some View {
        let hasClipboard = InspectorSectionModel.supportsClipboard(component.type)
        let isMeshRenderer = InspectorSectionModel.isMeshRenderer(component.type)
        return InspectorSectionView(
            title: InspectorSectionModel.title(forComponentName: component.name),
            onReset: InspectorSectionModel.supportsReset(component.type) ? {
                resetTransform(entityId: entityId)
                refreshView()
            } : nil,
            onCopy: hasClipboard ? {
                if isMeshRenderer {
                    clipboard.copyMaterial(of: entityId, meshIndex: 0)
                } else {
                    clipboard.copyTransform(of: entityId)
                }
            } : nil,
            onPaste: hasClipboard ? {
                if isMeshRenderer {
                    clipboard.pasteMaterial(into: entityId, meshIndex: 0)
                } else {
                    clipboard.pasteTransform(into: entityId)
                }
                refreshView()
            } : nil,
            canPaste: isMeshRenderer ? clipboard.material != nil : clipboard.transform != nil,
            onRemove: canRemoveComponentFromInspector(componentType: component.type, from: entityId) ? {
                removeComponentFromEntity_Editor(componentType: component.type)
            } : nil
        ) {
            component.view(entityId, selectedAsset, refreshView)
        }
    }
}
