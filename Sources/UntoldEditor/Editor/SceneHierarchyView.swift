//
//  SceneHierarchyView.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// Icon for a hierarchy row. Lights map to their primitive (matching the Add
/// menu); asset nodes keep their asset icons. The engine doesn't store which
/// mesh primitive an entity is, so everything else falls back to a cube.
func hierarchyIconName(for entityId: EntityID) -> String {
    if hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self) {
        return "sun.max"
    }
    if hasComponent(entityId: entityId, componentType: PointLightComponent.self) {
        return "lightbulb"
    }
    if hasComponent(entityId: entityId, componentType: SpotLightComponent.self) {
        return "flashlight.on.fill"
    }
    if hasComponent(entityId: entityId, componentType: AreaLightComponent.self) {
        return "square"
    }
    if isDerivedAssetNode(entityId) {
        return isBindableAssetMeshNode(entityId) ? "cube.fill" : "square.stack.3d.up"
    }
    return "cube"
}

/// The "add entity" actions, bundled so the same menu can be reused by the
/// bottom "+" toolbar and the right-click context menu.
struct AddEntityActions {
    var empty: () -> Void = {}
    var cube: () -> Void = {}
    var sphere: () -> Void = {}
    var plane: () -> Void = {}
    var dirLight: () -> Void = {}
    var pointLight: () -> Void = {}
    var spotLight: () -> Void = {}
    var areaLight: () -> Void = {}
}

@ViewBuilder
func addEntityMenuItems(_ actions: AddEntityActions) -> some View {
    Button("Empty Entity", systemImage: "plus") { actions.empty() }
    Divider()
    Button("Cube", systemImage: "cube") { actions.cube() }
    Button("Sphere", systemImage: "circle") { actions.sphere() }
    Button("Plane", systemImage: "square") { actions.plane() }
    Divider()
    Button("Directional Light", systemImage: "sun.max") { actions.dirLight() }
    Button("Point Light", systemImage: "lightbulb") { actions.pointLight() }
    Button("Spot Light", systemImage: "flashlight.on.fill") { actions.spotLight() }
    Button("Area Light", systemImage: "square") { actions.areaLight() }
}

struct SceneHierarchyView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @ObservedObject var sceneCatalog: ProjectSceneCatalog
    var projectName: String
    var activeSceneURL: URL?
    var onSelectScene: (URL) -> Void
    var isPlaying: Bool
    var onTogglePlay: () -> Void
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
    var onDeleteEntity: (EntityID) -> Void = { _ in }

    @State private var activeSceneExpanded = true

    private var addActions: AddEntityActions {
        AddEntityActions(
            empty: onAddEntity_Editor,
            cube: onAddCube,
            sphere: onAddSphere,
            plane: onAddPlane,
            dirLight: onAddDirLight,
            pointLight: onAddPointLight,
            spotLight: onAddSpotLight,
            areaLight: onAddAreaLight
        )
    }

    /// A scene node in the tree. `url == nil` represents the current, not-yet-saved
    /// ("Untitled") scene, which is always the active one.
    private struct SceneItem: Identifiable {
        let url: URL?
        let name: String
        let isActive: Bool
        var id: String {
            url?.absoluteString ?? "__untitled__"
        }
    }

    private var sceneItems: [SceneItem] {
        var items: [SceneItem] = []
        let active = activeSceneURL
        let activeInCatalog = active.map { url in sceneCatalog.scenes.contains { $0.url == url } } ?? false

        // Active scene always shows live elements. If it isn't an on-disk scene
        // in the catalog, surface it as a synthetic "Untitled Scene" entry.
        if active == nil || activeInCatalog == false {
            items.append(SceneItem(
                url: active,
                name: active?.deletingPathExtension().lastPathComponent ?? "Untitled Scene",
                isActive: true
            ))
        }

        for scene in sceneCatalog.scenes {
            items.append(SceneItem(url: scene.url, name: scene.name, isActive: scene.url == active))
        }
        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Project header

            projectRow

            // MARK: - Scenes / Elements tree

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sceneItems) { item in
                        sceneRow(item)

                        if item.isActive, activeSceneExpanded {
                            ForEach(sceneGraphModel.getChildren(entityId: nil), id: \.self) { entityId in
                                HierarchyNode(
                                    entityId: entityId,
                                    entityName: getEntityName(entityId: entityId),
                                    depth: 0,
                                    sceneGraphModel: sceneGraphModel,
                                    selectionManager: selectionManager,
                                    onParentEntity: onParentEntity,
                                    onUnparentEntity: onUnparentEntity,
                                    onDeleteEntity: onDeleteEntity,
                                    addActions: addActions
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
            .background(Color.editorFillSubtle)
            .cornerRadius(8)
        }
        .padding(5)
        .frame(minWidth: 320, maxWidth: 320, maxHeight: .infinity)
        .background(Color.editorBackground)
        .cornerRadius(8)
        .shadow(color: Color.editorShadow, radius: 3, x: 0, y: 1)
        .padding(5)
    }

    // MARK: - Project row (tree root)

    private var projectRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(.editorAccent)
            Text(projectName)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)

            Spacer()

            playButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selectionManager.projectSelected ? Color.editorAccentSoft : Color.editorFill)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selectionManager.projectSelected ? Color.editorAccent : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectionManager.selectProject()
        }
    }

    private var playButton: some View {
        Button(action: onTogglePlay) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.editorTextPrimary)
                .frame(width: 26, height: 26)
                .background(isPlaying ? Color.editorSecondaryAccent : Color.editorAccent)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(isPlaying ? "Stop play mode" : "Enter play mode")
    }

    // MARK: - Scene row (second level)

    private func sceneRow(_ item: SceneItem) -> some View {
        let isSceneSelected = item.isActive && selectionManager.sceneSelected
        return HStack(spacing: 8) {
            if item.isActive {
                Button(action: { activeSceneExpanded.toggle() }) {
                    Image(systemName: activeSceneExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: 12)
                }
                .buttonStyle(.plain)
                .focusable(false)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }

            Image(systemName: item.isActive ? "film.fill" : "film")
                .foregroundColor(item.isActive ? .editorAccent : .editorTextTertiary)

            Text(item.name)
                .fontWeight(item.isActive ? .semibold : .regular)
                .foregroundColor(item.isActive ? .editorTextPrimary : .editorTextSecondary)
                .lineLimit(1)

            Spacer()

            if item.isActive {
                Menu {
                    addEntityMenuItems(addActions)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.editorTextPrimary)
                        .frame(width: 20, height: 20)
                        .background(Color.editorInfo)
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add to scene")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSceneSelected ? Color.editorAccentSoft : (item.isActive ? Color.editorSurface.opacity(0.5) : Color.clear))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSceneSelected ? Color.editorAccent : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isActive {
                // Select the active scene (its properties show in the Inspector).
                selectionManager.selectScene()
            } else if let url = item.url {
                onSelectScene(url)
            }
        }
        .help(item.isActive ? "Select scene" : "Load this scene")
    }
}

// MARK: - Entity Row

struct EntityRow: View {
    let entityid: EntityID
    let entityName: String
    var hasChildren: Bool = false
    var isExpanded: Bool = true
    var onToggleExpanded: () -> Void = {}
    @ObservedObject var selectionManager: SelectionManager
    @State private var isDragOver = false

    private var isSelected: Bool {
        entityid == selectionManager.selectedEntity
    }

    private var isAssetNode: Bool {
        isDerivedAssetNode(entityid)
    }

    var body: some View {
        if isAssetNode {
            styledEntityRow
        } else {
            styledEntityRow
                .draggable(String(entityid))
        }
    }

    private var styledEntityRow: some View {
        entityRowContent
            .padding(8)
            .background(isSelected ? Color.editorSurface : Color.clear)
            .cornerRadius(6)
    }

    private var entityRowContent: some View {
        HStack(spacing: 8) {
            Button(action: onToggleExpanded) {
                Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(hasChildren ? .editorTextSecondary : .clear)
                    .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(hasChildren == false)
            .help(isExpanded ? "Collapse Children" : "Expand Children")

            Image(systemName: hierarchyIconName(for: entityid))
                .foregroundColor(isSelected ? .editorTextPrimary : (isAssetNode ? .editorTextSecondary : .editorTextTertiary))

            Text(entityName)
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundColor(isSelected ? .editorTextPrimary : (isAssetNode ? .editorTextSecondary : .editorTextPrimary))

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
    var onDeleteEntity: (EntityID) -> Void = { _ in }
    var addActions: AddEntityActions = .init()
    @State private var isDragOver = false

    var body: some View {
        nodeContent
    }

    private var nodeContent: some View {
        let children = sceneGraphModel.getChildren(entityId: entityId)
        let hasChildren = children.isEmpty == false
        let isExpanded = sceneGraphModel.isExpanded(entityId: entityId)

        return VStack(alignment: .leading, spacing: 4) {
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
            // Indent one chevron-slot (chevron width 12 + HStack spacing 8) per
            // level, so a child's chevron lines up under its parent's icon.
            .padding(.leading, CGFloat(depth) * 20)
            .onTapGesture {
                selectionManager.inspectEntity(entityId: entityId)
            }
            .contextMenu {
                contextMenuContent
            }
            .onDrop(of: [.text], isTargeted: $isDragOver) { providers in
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
                        onParentEntity: onParentEntity,
                        onUnparentEntity: onUnparentEntity,
                        onDeleteEntity: onDeleteEntity,
                        addActions: addActions
                    )
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard isDerivedAssetNode(entityId) == false else { return false }
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
        AddEntityActions(
            empty: { addChild(addActions.empty) },
            cube: { addChild(addActions.cube) },
            sphere: { addChild(addActions.sphere) },
            plane: { addChild(addActions.plane) },
            dirLight: { addChild(addActions.dirLight) },
            pointLight: { addChild(addActions.pointLight) },
            spotLight: { addChild(addActions.spotLight) },
            areaLight: { addChild(addActions.areaLight) }
        )
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
