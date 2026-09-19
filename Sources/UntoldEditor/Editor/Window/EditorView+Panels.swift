//
//  EditorView+Panels.swift
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

extension EditorView {
    /// Builds the panels for the docking layout from the root view's state.
    var dockRegistry: EditorPanelRegistry {
        EditorPanelRegistry(
            content: { panel in panelContent(panel) },
            accessories: { panel in panelAccessories(panel) }
        )
    }

    /// A panel's own filter text; each panel keeps its own.
    func panelSearch(_ panel: PanelID) -> Binding<String> {
        Binding(
            get: { panelSearchText[panel] ?? "" },
            set: { panelSearchText[panel] = $0 }
        )
    }

    func panelContent(_ panel: PanelID) -> AnyView {
        switch panel {
        case .hierarchy:
            return AnyView(SceneHierarchyView(
                selectionManager: selectionManager,
                sceneGraphModel: sceneGraphModel,
                sceneCatalog: sceneCatalog,
                projectName: editorBasePath.projectName ?? "Untitled Project",
                activeSceneURL: editorController?.currentSceneURL,
                onSelectScene: editor_requestLoadScene,
                entityList: editor_entities,
                onAddEntity_Editor: editor_addNewEntity,
                onRemoveEntity_Editor: editor_removeEntity,
                onParentEntity: editor_parentEntity,
                onUnparentEntity: editor_unparentEntity,
                onDeleteEntity: editor_removeEntity(_:),
                onDropRow: { payload, parent in
                    editor_placeDroppedRow(payload, parent: parent)
                }
            ))
        case .viewport:
            return AnyView(editorSceneViewport)
        case .inspector:
            return AnyView(editorRightPanel)
        case .assets:
            return AnyView(AssetBrowserView(
                assets: $assets,
                selectedAsset: $selectedAsset,
                navigation: assetBrowserNavigation,
                selectionManager: selectionManager,
                sceneGraphModel: sceneGraphModel,
                searchQuery: panelSearch(.assets),
                editor_addEntityWithAsset: editor_addEntityWithAsset,
                editor_loadSceneAuthoredFromAsset: editor_loadSceneAuthoredFromAsset
            ))
        case .explore:
            return AnyView(AssetPackBrowserView(searchQuery: panelSearch(.explore)) {
                NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
            })
        case .console:
            return AnyView(LogConsoleView(searchQuery: panelSearch(.console), autoScroll: $consoleAutoScroll))
        case .tasks:
            return AnyView(TasksPanelView(searchQuery: panelSearch(.tasks)))
        case .plugins:
            return AnyView(ComponentsPanelView(searchQuery: panelSearch(.plugins)))
        }
    }

    /// The controls that go with a panel in its tab strip: a filter field, and for
    /// the console and the tasks their buttons. The strip sizes them: beside the
    /// tabs in the bottom area, on their own row in a side area.
    func panelAccessories(_ panel: PanelID) -> AnyView? {
        switch panel {
        case .assets, .explore, .plugins:
            return AnyView(EditorSearchField(text: panelSearch(panel), placeholder: "Filter \(panel.title.lowercased())"))
        case .console:
            return AnyView(HStack(spacing: 8) {
                EditorSearchField(text: panelSearch(.console), placeholder: "Filter log")
                Toggle("Auto-scroll", isOn: $consoleAutoScroll)
                    .toggleStyle(.checkbox)
                    .font(EditorType.hint)
                EditorIconButton(systemImage: "trash", size: 22, help: "Clear console") {
                    LogStore.shared.clear()
                }
            })
        case .tasks:
            return AnyView(HStack(spacing: 8) {
                EditorSearchField(text: panelSearch(.tasks), placeholder: "Filter tasks")
                EditorIconButton(systemImage: "stop.circle", size: 22, help: "Cancel all running tasks") {
                    taskCenter.cancelAll()
                }
                .disabled(taskCenter.activeCount == 0)
                EditorIconButton(systemImage: "trash", size: 22, help: "Clear finished tasks") {
                    taskCenter.clearFinished()
                }
            })
        case .hierarchy, .viewport, .inspector:
            return nil
        }
    }
}
