//
//  SelectionSeveralPanelsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import ModelIO
import simd
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// Several selected entities in the panels: the hierarchy's rows and footer,
/// the Inspector, and the keys that act on the selection.
final class SelectionSeveralPanelsTests: XCTestCase {
    private var originalScene: UntoldEngine.Scene!
    private var originalActiveEntity: EntityID!
    private var originalTool: TransformTool!
    private var originalBoxBuffer: MTLBuffer?
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!
    private var selectedAsset: Asset?

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
        originalBoxBuffer = bufferResources.boundingBoxBuffer
        bufferResources.boundingBoxBuffer = device.makeBuffer(
            length: MemoryLayout<simd_float4>.stride * boundingBoxVertexCount,
            options: .storageModeShared
        )

        originalScene = scene
        originalActiveEntity = activeEntity
        originalTool = EditorViewportSettings.shared.tool
        scene = UntoldEngine.Scene()
        activeEntity = .invalid
        gizmoTargets = []
        EditorViewportSettings.shared.tool = .move
        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
    }

    override func tearDown() {
        selectionManager.clearSelection()
        selectionManager = nil
        sceneGraphModel = nil
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        EditorViewportSettings.shared.tool = originalTool
        activeEntity = originalActiveEntity
        bufferResources.boundingBoxBuffer = originalBoxBuffer
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    private func makeBox(_ name: String, at position: simd_float3 = .zero) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        registerComponent(entityId: entity, componentType: RenderComponent.self)
        scene.get(component: LocalTransformComponent.self, for: entity)?.boundingBox = (
            min: simd_float3(repeating: -0.5),
            max: simd_float3(repeating: 0.5)
        )
        translateTo(entityId: entity, position: position)
        return entity
    }

    private func makeInspector() -> InspectorView {
        InspectorView(
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            onAddName_Editor: {},
            selectedAsset: Binding(get: { self.selectedAsset }, set: { self.selectedAsset = $0 })
        )
    }

    // MARK: - A click on a row of the hierarchy

    func test_aClickOnARow_selectsItAlone() {
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: false, modifiers: []), .select)
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: false, modifiers: [.option]), .select)
    }

    func test_aClickWithShiftOrCommand_addsTheRowOrTakesItOut() {
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: false, modifiers: [.shift]), .toggle)
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: false, modifiers: [.command]), .toggle)
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: false, modifiers: [.command, .shift]), .toggle)
    }

    func test_fromPlayToStop_aClickOnARowDoesNothing() {
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: true, modifiers: []), .none)
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: true, modifiers: [.shift]), .none)
        XCTAssertEqual(HierarchyRowClick.click(isPlaying: true, modifiers: [.command]), .none)
    }

    // MARK: - The footer

    func test_theFooter_countsEverySelectedEntity() {
        XCTAssertEqual(HierarchyFooterView.summary(entityCount: 12, selectedCount: 3), "12 entities · 3 selected")
    }

    func test_theFooter_saysWhyNothingIsSelectedWhilePlaying() {
        XCTAssertEqual(
            HierarchyFooterView.summary(entityCount: 12, selectedCount: 3, isPlaying: true),
            "12 entities · no selecting while playing"
        )
    }

    // MARK: - The Inspector

    func test_theInspector_showsTheOneSelectedEntity() {
        let box = makeBox("Box")
        selectionManager.inspectEntity(entityId: box)

        XCTAssertEqual(makeInspector().inspectedEntity, box)
    }

    func test_withSeveralSelected_theInspectorShowsNoneOfThem() {
        selectionManager.selectEntities([makeBox("First"), makeBox("Second")])

        XCTAssertNil(makeInspector().inspectedEntity)
        XCTAssertEqual(InspectorSeveralSelectedView.title(count: 2), "2 entities selected")
    }

    func test_thePinnedEntity_staysInTheInspector_withSeveralSelected() {
        let pinned = makeBox("Pinned")
        sceneGraphModel.refreshHierarchy()
        selectionManager.togglePinnedInspection(pinned)
        selectionManager.selectEntities([makeBox("First"), makeBox("Second")])

        XCTAssertEqual(makeInspector().inspectedEntity, pinned)
    }

    func test_backToOneEntity_theInspectorShowsIt() {
        let first = makeBox("First"), second = makeBox("Second")
        selectionManager.selectEntities([first, second])

        selectionManager.toggleSelection(of: second)

        XCTAssertEqual(makeInspector().inspectedEntity, first)
    }

    // MARK: - H

    func test_hidingTheSelection_hidesEveryOneOfThem() {
        let first = makeBox("First"), second = makeBox("Second"), other = makeBox("Other")
        selectionManager.selectEntities([first, second])

        selectionManager.hideSelection()

        XCTAssertTrue(selectionManager.isHidden(first))
        XCTAssertTrue(selectionManager.isHidden(second))
        XCTAssertFalse(selectionManager.isHidden(other))
        XCTAssertEqual(scene.get(component: RenderComponent.self, for: first)?.isVisible, false)
        XCTAssertEqual(scene.get(component: RenderComponent.self, for: second)?.isVisible, false)
        XCTAssertEqual(scene.get(component: RenderComponent.self, for: other)?.isVisible, true)
        XCTAssertEqual(selectionManager.selectedEntities, [first, second], "hidden, they stay selected")
        XCTAssertFalse(gizmoActive, "and the gizmo leaves them")
        XCTAssertTrue(SelectionHighlights.shared.boxes.isEmpty)
    }

    func test_hidingTheSelection_ofOneEntity_hidesIt() {
        let box = makeBox("Box")
        selectionManager.inspectEntity(entityId: box)

        selectionManager.hideSelection()

        XCTAssertTrue(selectionManager.isHidden(box))
        XCTAssertEqual(selectionManager.selectedEntity, box)
        XCTAssertFalse(gizmoActive)
    }

    func test_hidingTheSelection_withNothingSelected_hidesNothing() {
        let box = makeBox("Box")

        selectionManager.hideSelection()

        XCTAssertFalse(selectionManager.isHidden(box))
        XCTAssertTrue(selectionManager.hiddenEntities.isEmpty)
    }

    func test_showingEverything_bringsTheGizmoBackToAllOfThem() {
        let first = makeBox("First", at: simd_float3(-2, 0, 0)), second = makeBox("Second", at: simd_float3(2, 0, 0))
        selectionManager.selectEntities([first, second])
        selectionManager.hideSelection()

        selectionManager.showAllEntities()

        XCTAssertTrue(gizmoActive)
        XCTAssertEqual(gizmoTargets, [first, second])
        XCTAssertEqual(SelectionHighlights.shared.boxes.map(\.entityId), [first, second])
    }

    // MARK: - The hints

    func test_whereTheViewportSelects_selectingIsHinted() {
        let hints = ViewportHints.hints(style: .classic, hasSelection: false, canSelect: true)

        XCTAssertEqual(hints.first, ViewportHints.select)
        XCTAssertFalse(hints.contains(ViewportHints.addToSelection), "there is nothing to add to")
        XCTAssertEqual(hints.map(\.action), ["Select", "Look", "Fly", "Zoom", "Pan", "Move", "Orbit"])
    }

    func test_withASelection_addingToItIsHinted() {
        let hints = ViewportHints.hints(style: .classic, hasSelection: true, canSelect: true)

        XCTAssertEqual(Array(hints.prefix(3)), [ViewportHints.frameSelection, ViewportHints.select, ViewportHints.addToSelection])
        XCTAssertEqual(ViewportHints.addToSelection.keys, "⇧ Click")
        XCTAssertEqual(ViewportHints.select.keys, "Click or drag")
    }

    func test_whereTheViewportDoesNotSelect_asInExploreMode_selectingIsNotHinted() {
        let hints = ViewportHints.hints(style: .classic, hasSelection: false)

        XCTAssertFalse(hints.contains(ViewportHints.select))
        XCTAssertFalse(hints.contains(ViewportHints.addToSelection))
    }
}
