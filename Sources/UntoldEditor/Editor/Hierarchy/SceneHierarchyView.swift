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

struct SceneHierarchyView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @ObservedObject var sceneCatalog: ProjectSceneCatalog
    var projectName: String
    var activeSceneURL: URL?
    var onSelectScene: (URL) -> Void
    var isPlaying: Bool
    var onTogglePlay: () -> Void
    /// True while an async post-Play restore is in flight; disables the button
    /// to prevent re-entrant Play/Stop toggling mid-restore.
    var isPlayModeBusy: Bool = false
    var entityList: [EntityID]
    var onAddEntity_Editor: () -> Void
    var onRemoveEntity_Editor: () -> Void
    var onParentEntity: (EntityID, EntityID) -> Void = { _, _ in }
    var onUnparentEntity: (EntityID) -> Void = { _ in }
    var onDeleteEntity: (EntityID) -> Void = { _ in }
    /// An asset browser or Lights shelf row dropped on the tree: on the scene row
    /// the parent is `nil` (scene root), on an entity row it is that entity.
    var onDropRow: (DroppedRowPayload, EntityID?) -> Void = { _, _ in }

    @State private var activeSceneExpanded = true
    @State private var isSceneDropTargeted = false

    private var addActions: AddEntityActions {
        AddEntityActions(empty: onAddEntity_Editor)
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
                                    onDropRow: onDropRow,
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
        .disabled(isPlayModeBusy)
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
        .background(sceneRowBackground(item, isSelected: isSceneSelected))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSceneSelected ? Color.editorAccent : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        // Only the active scene takes asset drops (they go to the scene root);
        // entity-id plain text from a hierarchy row does not conform to the
        // payload type, so it is not accepted here.
        .onDrop(of: [AssetDragPayload.contentType], isTargeted: item.isActive ? $isSceneDropTargeted : .constant(false)) { providers in
            guard item.isActive else { return false }
            return loadDroppedRowPayload(from: providers) { payload in
                onDropRow(payload, nil)
            }
        }
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

    private func sceneRowBackground(_ item: SceneItem, isSelected: Bool) -> Color {
        if item.isActive, isSceneDropTargeted {
            return Color.editorInfo.opacity(0.2)
        }
        if isSelected {
            return Color.editorAccentSoft
        }
        return item.isActive ? Color.editorSurface.opacity(0.5) : Color.clear
    }
}
