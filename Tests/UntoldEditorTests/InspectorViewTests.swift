//
//  InspectorViewTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import ModelIO
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class InspectorViewTests: XCTestCase {
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!
    private var selectedAsset: Asset?
    private var sut: InspectorView!

    override func setUp() {
        super.setUp()
        // Snapshot current scene and inject a fresh one
        scene = Scene()

        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
        selectedAsset = nil
        EditorComponentsState.shared.clear()

        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Metal device is not available.")
            return
        }

        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
    }

    override func tearDown() {
        // Restore original scene
        EditorComponentsState.shared.clear()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSUT(onAddName: @escaping () -> Void = {}) -> InspectorView {
        InspectorView(
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            onAddName_Editor: onAddName,
            selectedAsset: Binding(get: { self.selectedAsset }, set: { self.selectedAsset = $0 })
        )
    }

    private func createEntityWithName(_ name: String) -> EntityID {
        let e = createEntity()
        setEntityName(entityId: e, name: name)
        return e
    }

    private func addTransform(to e: EntityID) {
        registerComponent(entityId: e, componentType: LocalTransformComponent.self)
        registerComponent(entityId: e, componentType: WorldTransformComponent.self)
    }

    private func addRender(to e: EntityID) {
        registerComponent(entityId: e, componentType: RenderComponent.self)
    }

    private func addAnimation(to e: EntityID) {
        registerComponent(entityId: e, componentType: AnimationComponent.self)
    }

    private func addKinetic(to e: EntityID) {
        registerComponent(entityId: e, componentType: PhysicsComponents.self)
        registerComponent(entityId: e, componentType: KineticComponent.self)
    }

    // MARK: - Tests

    func test_nameEditing_updatesEntityName_andRefreshesHierarchy() {
        // Arrange
        let e = createEntityWithName("Old Name")
        addTransform(to: e) // ensure Inspector shows Transform editor too
        selectionManager.selectedEntity = e

        var onAddNameCalled = false
        sut = makeSUT(onAddName: { onAddNameCalled = true })

        // Act: Simulate changing the name through the same API InspectorView uses
        setEntityName(entityId: e, name: "New Name")
        sut.selectionManager.objectWillChange.send()
        sut.sceneGraphModel.refreshHierarchy()

        // Assert
        XCTAssertEqual(getEntityName(entityId: e), "New Name", "Entity name should be updated.")
        XCTAssertTrue(onAddNameCalled == false, "onAddName is invoked on TextField submit; we didn’t simulate submit here.")
    }

    func test_mergeAndSortComponents_showsExpectedEditors() {
        // Arrange
        let e = createEntityWithName("Entity")
        addTransform(to: e)
        addRender(to: e)
        addAnimation(to: e)
        addKinetic(to: e)
        selectionManager.selectedEntity = e

        sut = makeSUT()

        // Act
        let merged = mergeEntityComponents(selectedEntity: e, editor_availableComponents: availableComponents_Editor)
        let sorted = sortEntityComponents(componentOption_Editor: merged)

        let expected = ["Render Component", "Transform Component", "Animation Component", "Kinetic Component"]
        let names = Array(sorted.map(\.name).prefix(expected.count))
        XCTAssertEqual(names, expected, "Components should be sorted as expected.")
    }

    func test_addComponentSheet_addsDirectionalLight_andCreatesLightComponent() {
        // Arrange
        let e = createEntityWithName("Light Holder")
        addTransform(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        XCTAssertFalse(hasComponent(entityId: e, componentType: DirectionalLightComponent.self))
        XCTAssertFalse(hasComponent(entityId: e, componentType: LightComponent.self))

        // Act: call the same function InspectorView uses when selecting from the sheet
        sut.addComponentToEntity_Editor(componentType: DirectionalLightComponent.self)

        // Assert: engine created the correct components
        XCTAssertTrue(hasComponent(entityId: e, componentType: DirectionalLightComponent.self),
                      "DirectionalLightComponent should be present after adding.")
        XCTAssertTrue(hasComponent(entityId: e, componentType: LightComponent.self),
                      "LightComponent should be present for a directional light.")
    }

    func test_kineticEditor_changesMass_viaBinding() {
        // Arrange
        let e = createEntityWithName("Phys")
        addTransform(to: e)
        addKinetic(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        let initialMass = getMass(entityId: e)

        // Act: mimic the binding setter used by TextInputNumberView in KineticEditorView
        setMass(entityId: e, mass: initialMass + 5.0)
        sut.selectionManager.objectWillChange.send()

        // Assert
        XCTAssertEqual(getMass(entityId: e), initialMass + 5.0, accuracy: 0.0001)
    }

    func test_pointLightEditor_changesIntensity_viaBinding() {
        // Arrange
        let e = createEntityWithName("Point")
        addTransform(to: e)
        createPointLight(entityId: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        let initialIntensity = getLightIntensity(entityId: e)

        // Act: mimic the binding setter used by PointLightEditorView
        updateLightIntensity(entityId: e, intensity: initialIntensity + 2.0)
        sut.selectionManager.objectWillChange.send()

        // Assert
        XCTAssertEqual(getLightIntensity(entityId: e), initialIntensity + 2.0, accuracy: 0.0001)
    }
}
