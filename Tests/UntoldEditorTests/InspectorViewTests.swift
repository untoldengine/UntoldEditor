//
//  InspectorViewTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

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

        let expected = ["Render Component", "Transform Component"]
        let names = Array(sorted.map(\.name).prefix(expected.count))
        XCTAssertEqual(names, expected, "Components should be sorted as expected.")
    }

    func test_renderComponentEditor_togglesShadowCasting_viaBinding() {
        // Arrange
        let e = createEntityWithName("Receiver Plane")
        addTransform(to: e)
        addRender(to: e)

        XCTAssertTrue(getEntityCastsShadow(entityId: e))

        // Act: mimic the binding setter used by RenderComponentEditorView.
        setEntityCastsShadow(entityId: e, false)

        // Assert
        XCTAssertFalse(getEntityCastsShadow(entityId: e))
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

    func test_pointLightEditor_togglesShadowCasting_viaBinding() {
        // Arrange
        let e = createEntityWithName("Point")
        addTransform(to: e)
        createPointLight(entityId: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        XCTAssertFalse(getPointLightCastsShadow(entityId: e))

        // Act: mimic the binding setter used by PointLightEditorView
        setLight(entityId: e, .point(.castsShadow(true)))
        sut.selectionManager.objectWillChange.send()

        // Assert
        XCTAssertTrue(getPointLightCastsShadow(entityId: e))
    }

    func test_spotLightEditor_togglesShadowCasting_viaBinding() {
        // Arrange
        let e = createEntityWithName("Spot")
        addTransform(to: e)
        createSpotLight(entityId: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        XCTAssertFalse(getSpotLightCastsShadow(entityId: e))

        // Act: mimic the binding setter used by SpotLightEditorView
        setLight(entityId: e, .spot(.castsShadow(true)))
        sut.selectionManager.objectWillChange.send()

        // Assert
        XCTAssertTrue(getSpotLightCastsShadow(entityId: e))
    }

    func test_removeComponent_isDisabledForDirectionalLightInSceneCompositionMode() {
        // Arrange
        let e = createEntityWithName("Light Entity")
        addTransform(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Add DirectionalLightComponent
        sut.addComponentToEntity_Editor(componentType: DirectionalLightComponent.self)

        // Precondition: Verify component was added
        XCTAssertTrue(hasComponent(entityId: e, componentType: DirectionalLightComponent.self),
                      "DirectionalLightComponent should be present after adding.")
        XCTAssertTrue(hasComponent(entityId: e, componentType: LightComponent.self),
                      "LightComponent should be present after adding directional light.")

        // Act: Removal is disabled in scene composition mode
        sut.removeComponentFromEntity_Editor(componentType: DirectionalLightComponent.self)

        // Assert: Component remains because inspector-side removal is disabled
        XCTAssertTrue(hasComponent(entityId: e, componentType: DirectionalLightComponent.self),
                      "DirectionalLightComponent removal should be disabled in scene composition mode.")
    }

    func test_removeComponent_doesNotRemoveKinetic_whenRemovalIsDisabled() {
        // Arrange
        let e = createEntityWithName("Physics Entity")
        addTransform(to: e)
        addKinetic(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition: Verify component exists
        XCTAssertTrue(hasComponent(entityId: e, componentType: KineticComponent.self),
                      "KineticComponent should be present initially.")

        // Act: Remove the KineticComponent
        sut.removeComponentFromEntity_Editor(componentType: KineticComponent.self)

        // Assert: Component remains because removal is disabled
        XCTAssertTrue(hasComponent(entityId: e, componentType: KineticComponent.self),
                      "KineticComponent removal should be disabled in scene composition mode.")
    }

    func test_removeComponent_doesNotRemoveFromEditorState_whenRemovalIsDisabled() {
        // Arrange
        let e = createEntityWithName("Test Entity")
        addTransform(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Add PointLightComponent
        sut.addComponentToEntity_Editor(componentType: PointLightComponent.self)

        let key = ObjectIdentifier(PointLightComponent.self)

        // Precondition: Verify component is in editor state
        XCTAssertNotNil(EditorComponentsState.shared.components[e]?[key],
                        "Component should be in editor state after adding.")

        // Act: Remove the component
        sut.removeComponentFromEntity_Editor(componentType: PointLightComponent.self)

        // Assert: Component remains in editor state because removal is disabled
        XCTAssertNotNil(EditorComponentsState.shared.components[e]?[key],
                        "Component should remain in editor state when removal is disabled.")
    }

    func test_addComponentSheet_doesNotAddGaussianComponent_inSceneCompositionMode() {
        // Arrange
        let e = createEntityWithName("Gaussian Holder")
        addTransform(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Precondition
        XCTAssertFalse(hasComponent(entityId: e, componentType: GaussianComponent.self),
                       "GaussianComponent should not be present initially.")

        // Act: Gaussian authoring is disabled in scene composition mode
        sut.addComponentToEntity_Editor(componentType: GaussianComponent.self)

        // Assert: Component should not be added to editor state
        let key = ObjectIdentifier(GaussianComponent.self)
        XCTAssertNil(EditorComponentsState.shared.components[e]?[key],
                     "GaussianComponent should not be added from the inspector in scene composition mode.")
        XCTAssertFalse(hasComponent(entityId: e, componentType: GaussianComponent.self),
                       "GaussianComponent should not be registered in the engine.")
    }

    func test_removeComponent_doesNotRemoveGaussianComponent_whenRemovalIsDisabled() {
        // Arrange
        let e = createEntityWithName("Gaussian Entity")
        addTransform(to: e)
        selectionManager.selectedEntity = e
        sut = makeSUT()

        // Add GaussianComponent
        sut.addComponentToEntity_Editor(componentType: GaussianComponent.self)
        registerComponent(entityId: e, componentType: GaussianComponent.self)

        // Precondition: Verify component exists
        XCTAssertTrue(hasComponent(entityId: e, componentType: GaussianComponent.self),
                      "GaussianComponent should be present after adding.")

        // Act: Remove the GaussianComponent
        sut.removeComponentFromEntity_Editor(componentType: GaussianComponent.self)

        // Assert: Component remains because removal is disabled
        XCTAssertTrue(hasComponent(entityId: e, componentType: GaussianComponent.self),
                      "GaussianComponent removal should be disabled in scene composition mode.")

        // Assert: Inspector never authors Gaussian state in scene composition mode
        let key = ObjectIdentifier(GaussianComponent.self)
        XCTAssertNil(EditorComponentsState.shared.components[e]?[key],
                     "GaussianComponent should not have an inspector editor-state entry in scene composition mode.")
    }

    func test_mergeComponents_excludesGaussianComponent_inSceneCompositionMode() {
        // Arrange
        let e = createEntityWithName("Gaussian Entity")
        addTransform(to: e)
        registerComponent(entityId: e, componentType: GaussianComponent.self)
        selectionManager.selectedEntity = e

        sut = makeSUT()

        // Act
        let merged = mergeEntityComponents(selectedEntity: e, editor_availableComponents: availableComponents_Editor)

        // Assert: GaussianComponent should be hidden from inspector composition mode
        let key = ObjectIdentifier(GaussianComponent.self)
        XCTAssertNil(merged[key], "GaussianComponent should be excluded from merged components.")
    }
}
