//
//  SceneHierarchyView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import SwiftUI
import UntoldEngine

struct SceneHierarchyView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    var entityList: [EntityID]
    var onAddEntity_Editor: () -> Void
    var onRemoveEntity_Editor: () -> Void
    var onAddCube: () -> Void
    var onAddSphere: () -> Void
    var onAddPlane: () -> Void
    var onAddDirLight: () -> Void
    var onAddPointLight: () -> Void
    var onAddSpotLight: () -> Void
    var onAddAreaLight: () -> Void
    var onParentEntity: (EntityID, EntityID) -> Void = { _, _ in }
    var onUnparentEntity: (EntityID) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header with Add/Remove Buttons

            HStack {
                Image(systemName: "list.bullet.indent")
                    .foregroundColor(.accentColor)
                Text("Scene Graph")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                // Add Entity Menu
                Menu {
                    Button("Empty Entity", systemImage: "plus") { onAddEntity_Editor() }
                    Divider()
                    Button("Cube", systemImage: "cube.fill") { onAddCube() }
                    Button("Sphere", systemImage: "circle.fill") { onAddSphere() }
                    Button("Plane", systemImage: "rectangle.fill") { onAddPlane() }
                    Divider()
                    Button("Directional Light", systemImage: "sun.max") { onAddDirLight() }
                    Button("Point Light", systemImage: "lightbulb") { onAddPointLight() }
                    Button("Spot Light", systemImage: "flashlight.on.fill") { onAddSpotLight() }
                    Button("Area Light", systemImage: "square") { onAddAreaLight() }
                } label: {
                    Image(systemName: "plus")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                        .padding(8)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Add Entity")

                // Remove Entity Button
                Button(action: onRemoveEntity_Editor) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 18))
                }
                .buttonStyle(PlainButtonStyle())
                .help("Remove Selected Entity")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            // MARK: - Entity List

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sceneGraphModel.getChildren(entityId: nil), id: \.self) { entityId in
                        HierarchyNode(
                            entityId: entityId,
                            entityName: getEntityName(entityId: entityId),
                            depth: 0,
                            sceneGraphModel: sceneGraphModel,
                            selectionManager: selectionManager,
                            onParentEntity: onParentEntity,
                            onUnparentEntity: onUnparentEntity
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            .scrollContentBackground(.hidden)
            .frame(maxHeight: 300)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            Spacer() // Pushes content to the top
        }
        .frame(minWidth: 200, maxWidth: 200)
        .padding(8)
        .background(Color.editorBackground.ignoresSafeArea())
        .cornerRadius(12)
    }
}

// MARK: - Entity Row

struct EntityRow: View {
    let entityid: EntityID
    let entityName: String
    @ObservedObject var selectionManager: SelectionManager
    @State private var isDragOver = false

    private var isSelected: Bool {
        entityid == selectionManager.selectedEntity
    }

    var body: some View {
        entityRowContent
            .padding(8)
            .background(
                isSelected ? Color.gray.opacity(0.8) : Color.clear
            )
            .cornerRadius(6)
            .draggable(String(entityid))
    }

    private var entityRowContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "cube.fill")
                .foregroundColor(isSelected ? .white : .gray)

            Text(entityName)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()
        }
    }
}

struct HierarchyNode: View {
    let entityId: EntityID
    let entityName: String
    let depth: Int
    @ObservedObject var sceneGraphModel: SceneGraphModel
    let selectionManager: SelectionManager
    var onParentEntity: (EntityID, EntityID) -> Void = { _, _ in }
    var onUnparentEntity: (EntityID) -> Void = { _ in }
    @State private var isDragOver = false

    var body: some View {
        nodeContent
    }

    private var nodeContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            EntityRow(
                entityid: entityId,
                entityName: entityName,
                selectionManager: selectionManager
            )
            .contentShape(Rectangle())
            .padding(.leading, CGFloat(depth * 12))
            .onTapGesture {
                selectionManager.selectEntity(entityId: entityId)
            }
            .contextMenu {
                contextMenuContent
            }
            .onDrop(of: [.text], isTargeted: $isDragOver) { providers in
                handleDrop(providers: providers)
            }
            .background(
                isDragOver ?
                    Color.blue.opacity(0.2) :
                    Color.clear
            )

            // Children
            ForEach(sceneGraphModel.getChildren(entityId: entityId), id: \.self) { childID in
                HierarchyNode(
                    entityId: childID,
                    entityName: getEntityName(entityId: childID),
                    depth: depth + 1,
                    sceneGraphModel: sceneGraphModel,
                    selectionManager: selectionManager,
                    onParentEntity: onParentEntity,
                    onUnparentEntity: onUnparentEntity
                )
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            if let draggedEntityIdString = object as? String,
               let draggedValue = UInt64(draggedEntityIdString)
            {
                let draggedEntityId = EntityID(draggedValue)

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

    // Check if an entity is a descendant of another entity
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

    // Check if entity has a parent
    private var hasParent: Bool {
        getEntityParent(entityId: entityId) != nil
    }

    // Context menu for entity row
    private var contextMenuContent: some View {
        VStack {
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
            } else {
                Text("No parent")
                    .foregroundColor(.gray)
            }
        }
    }
}
