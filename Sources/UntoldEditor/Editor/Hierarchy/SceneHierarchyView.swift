//
//  SceneHierarchyView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The hierarchy panel: the loaded scene as the root row, the entity tree under
/// it, and a footer with the counts. The panel's strip holds the filter field
/// and the add menu; scenes are switched from the tabs above the viewport.
struct SceneHierarchyView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    /// The loaded scene's name, shown on the root row.
    var sceneName: String
    /// The filter typed in the panel's strip; blank shows everything.
    var filter: String = ""
    var onAddEntity_Editor: () -> Void
    var onParentEntity: (EntityID, EntityID) -> Void = { _, _ in }
    var onUnparentEntity: (EntityID) -> Void = { _ in }
    var onDeleteEntity: (EntityID) -> Void = { _ in }
    /// An asset browser or Lights shelf row dropped on the tree: on the root row
    /// the parent is `nil` (scene root), on an entity row it is that entity.
    var onDropRow: (DroppedRowPayload, EntityID?) -> Void = { _, _ in }

    @State private var isTreeExpanded = true

    private var addActions: AddEntityActions {
        AddEntityActions(empty: onAddEntity_Editor)
    }

    /// The rows the filter keeps; nil when there is no filter.
    private var visibleEntities: Set<EntityID>? {
        HierarchyFilter.visibleEntities(
            matching: filter,
            roots: sceneGraphModel.getChildren(entityId: nil),
            children: { sceneGraphModel.getChildren(entityId: $0) },
            name: { getEntityName(entityId: $0) }
        )
    }

    private var entityCount: Int {
        sceneGraphModel.childrenMap.values.reduce(0) { $0 + $1.count }
    }

    private var selectedCount: Int {
        guard let selected = selectionManager.selectedEntity, selected != .invalid else {
            return 0
        }
        return 1
    }

    var body: some View {
        let visible = visibleEntities
        let roots = sceneGraphModel.getChildren(entityId: nil).filter { visible?.contains($0) ?? true }

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SceneRootRow(
                        name: sceneName,
                        isExpanded: $isTreeExpanded,
                        isSelected: selectionManager.sceneSelected,
                        onSelect: { selectionManager.selectScene() },
                        onDropRow: { payload in onDropRow(payload, nil) }
                    )

                    if isTreeExpanded {
                        ForEach(roots, id: \.self) { entityId in
                            HierarchyNode(
                                entityId: entityId,
                                entityName: getEntityName(entityId: entityId),
                                depth: 0,
                                sceneGraphModel: sceneGraphModel,
                                selectionManager: selectionManager,
                                visibleEntities: visible,
                                onParentEntity: onParentEntity,
                                onUnparentEntity: onUnparentEntity,
                                onDeleteEntity: onDeleteEntity,
                                onDropRow: onDropRow,
                                addActions: addActions
                            )
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HierarchyFooterView(entityCount: entityCount, selectedCount: selectedCount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.editorPanelBackground)
    }
}
