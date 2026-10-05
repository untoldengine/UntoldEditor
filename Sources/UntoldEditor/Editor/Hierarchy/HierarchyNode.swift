//
//  HierarchyNode.swift
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

struct HierarchyNode: View {
    let entityId: EntityID
    let entityName: String
    let depth: Int
    @ObservedObject var sceneGraphModel: SceneGraphModel
    let selectionManager: SelectionManager
    /// The rows a filter keeps, nil when nothing is filtered. A filtered tree
    /// shows its matches expanded.
    var visibleEntities: Set<EntityID>?
    var onParentEntity: (EntityID, EntityID) -> Void = { _, _ in }
    var onUnparentEntity: (EntityID) -> Void = { _ in }
    var onDeleteEntity: (EntityID) -> Void = { _ in }
    var onDropRow: (DroppedRowPayload, EntityID?) -> Void = { _, _ in }
    var addActions: AddEntityActions = .init()
    /// True from Play to Stop, when a click on a row selects nothing.
    var isPlaying = false
    @State private var isDragOver = false

    var body: some View {
        nodeContent
    }

    private var nodeContent: some View {
        let children = sceneGraphModel.getChildren(entityId: entityId).filter(isShown)
        let hasChildren = children.isEmpty == false
        let isExpanded = visibleEntities != nil || sceneGraphModel.isExpanded(entityId: entityId)

        return VStack(alignment: .leading, spacing: 2) {
            EntityRow(
                entityid: entityId,
                entityName: entityName,
                hasChildren: hasChildren,
                isExpanded: isExpanded,
                onToggleExpanded: {
                    sceneGraphModel.toggleExpanded(entityId: entityId)
                },
                selectionManager: selectionManager
            )
            .contentShape(Rectangle())
            // One group indent per level, so a child's caret sits under its parent's icon.
            .padding(.leading, CGFloat(depth) * 16)
            .onTapGesture {
                switch HierarchyRowClick.click(isPlaying: isPlaying, modifiers: NSEvent.modifierFlags) {
                case .none:
                    break
                case .select:
                    selectionManager.inspectEntity(entityId: entityId)
                case .toggle:
                    selectionManager.toggleSelection(of: entityId)
                }
            }
            .contextMenu {
                contextMenuContent
            }
            .onDrop(of: [.text, AssetDragPayload.contentType], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }
            .background(
                isDragOver ?
                    Color.editorInfo.opacity(0.2) :
                    Color.clear
            )

            // Children
            if isExpanded {
                ForEach(children, id: \.self) { childID in
                    HierarchyNode(
                        entityId: childID,
                        entityName: getEntityName(entityId: childID),
                        depth: depth + 1,
                        sceneGraphModel: sceneGraphModel,
                        selectionManager: selectionManager,
                        visibleEntities: visibleEntities,
                        onParentEntity: onParentEntity,
                        onUnparentEntity: onUnparentEntity,
                        onDeleteEntity: onDeleteEntity,
                        onDropRow: onDropRow,
                        addActions: addActions,
                        isPlaying: isPlaying
                    )
                }
            }
        }
    }

    private func isShown(_ entityId: EntityID) -> Bool {
        visibleEntities?.contains(entityId) ?? true
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        // An asset browser or Lights shelf row: place it as a child of this node.
        // Asset nodes can't be parents, so a drop on one adds at the scene root instead.
        let droppedOnAssetNode = isDerivedAssetNode(entityId)
        if loadDroppedRowPayload(from: providers, completion: { payload in
            onDropRow(payload, droppedOnAssetNode ? nil : entityId)
        }) {
            return true
        }

        // Otherwise an entity id dragged from another row: reparent it here.
        guard droppedOnAssetNode == false else { return false }
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            if let draggedEntityIdString = object as? String,
               let draggedValue = UInt64(draggedEntityIdString)
            {
                let draggedEntityId = EntityID(draggedValue)
                guard isDerivedAssetNode(draggedEntityId) == false else { return }

                // Don't allow parenting to self
                if draggedEntityId == entityId {
                    print("⚠️ Cannot parent entity to itself")
                    return
                }

                // Check for circular dependency (if target is descendant of source)
                if isDescendant(entityId: entityId, potentialDescendant: draggedEntityId) {
                    print("⚠️ Cannot parent entity to its descendant")
                    return
                }

                // Parent the entity
                DispatchQueue.main.async {
                    onParentEntity(draggedEntityId, entityId)
                }
            }
        }

        return true // Return true immediately, async callback will handle the actual parenting
    }

    /// Check if an entity is a descendant of another entity
    private func isDescendant(entityId: EntityID, potentialDescendant: EntityID) -> Bool {
        let children = sceneGraphModel.getChildren(entityId: entityId)

        for child in children {
            if child == potentialDescendant {
                return true
            }
            // Recursively check descendants
            if isDescendant(entityId: child, potentialDescendant: potentialDescendant) {
                return true
            }
        }

        return false
    }

    /// Check if entity has a parent
    private var hasParent: Bool {
        getEntityParent(entityId: entityId) != nil
    }

    /// Run an "add" action and parent whatever new root entity it created to
    /// this node, so adding from an object nests the new object under it.
    private func addChild(_ create: () -> Void) {
        let before = Set(getAllGameEntities())
        create()
        let newRoots = getAllGameEntities().filter {
            before.contains($0) == false && getEntityParent(entityId: $0) == nil
        }
        for child in newRoots {
            onParentEntity(child, entityId)
        }
    }

    /// Add actions that parent the created entity to this node.
    private var parentedAddActions: AddEntityActions {
        AddEntityActions(empty: { addChild(addActions.empty) })
    }

    /// Context menu for entity row
    private var contextMenuContent: some View {
        VStack {
            Menu {
                // Adding from an object nests the new entity under it; asset
                // nodes can't be parents, so those add at scene root.
                addEntityMenuItems(isDerivedAssetNode(entityId) ? addActions : parentedAddActions)
            } label: {
                Label("Add", systemImage: "plus")
            }

            Divider()

            // The row's eye and lock, for the keyboard-less: same state, same toggles.
            Button(selectionManager.isHidden(entityId) ? "Show" : "Hide", systemImage: selectionManager.isHidden(entityId) ? "eye" : "eye.slash") {
                selectionManager.toggleHidden(entityId)
            }
            Button(selectionManager.isLocked(entityId) ? "Unlock" : "Lock", systemImage: selectionManager.isLocked(entityId) ? "lock.open" : "lock.fill") {
                selectionManager.toggleLocked(entityId)
            }

            Divider()

            if isDerivedAssetNode(entityId) {
                Text("Asset node")
                    .foregroundColor(.editorTextTertiary)
            } else {
                if hasParent {
                    Button(action: {
                        DispatchQueue.main.async {
                            onUnparentEntity(entityId)
                        }
                    }) {
                        HStack {
                            Image(systemName: "arrow.up.left")
                            Text("Unparent")
                        }
                    }
                    Divider()
                }

                Button(role: .destructive, action: {
                    DispatchQueue.main.async {
                        onDeleteEntity(entityId)
                    }
                }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete")
                    }
                }
            }
        }
    }
}
