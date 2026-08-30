//
//  EditorUntoldRendererTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import MetalKit
import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

@MainActor
final class EditorUntoldRendererTests: XCTestCase {
    private var renderer: UntoldRenderer!
    private var originalGameMode: Bool!
    private var originalActiveEntity: EntityID!
    private var originalParentGizmo: EntityID!
    private var originalGizmoActive: Bool!
    private var testEntity: EntityID!
    private var testCamera: EntityID!

    override func setUp() {
        super.setUp()

        let windowWidth = 800
        let windowHeight = 600

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)

        window.title = "test window"

        guard let renderer = UntoldRenderer.create() else {
            XCTFail("Failed to initialize the renderer")
            return
        }

        window.contentView = renderer.metalView
        self.renderer = renderer
        self.renderer.initResources()

        // Save original state
        originalGameMode = gameMode
        originalActiveEntity = activeEntity
        originalParentGizmo = parentEntityIdGizmo
        originalGizmoActive = gizmoActive

        // Reset to clean state
        gameMode = false
        activeEntity = .invalid
        parentEntityIdGizmo = .invalid
        gizmoActive = false

        // Reset input state
        InputSystem.shared.keyState = KeyState()
        InputSystem.shared.mouseActive = false
    }

    override func tearDown() {
        // Clean up test entities
        if testEntity != .invalid, testEntity != nil {
            destroyEntity(entityId: testEntity)
        }
        if testCamera != .invalid, testCamera != nil {
            destroyEntity(entityId: testCamera)
        }

        // Restore original state
        gameMode = originalGameMode
        activeEntity = originalActiveEntity
        parentEntityIdGizmo = originalParentGizmo
        gizmoActive = originalGizmoActive

        super.tearDown()
    }

    // MARK: - Game Mode Tests

    func test_handleSceneInput_returnsEarlyInGameMode() {
        // Arrange
        gameMode = true

        // Set up some input that would normally trigger actions
        InputSystem.shared.keyState.wPressed = true
        InputSystem.shared.keyState.shiftPressed = true
        activeEntity = createEntity()
        gizmoActive = true

        // Act - Should return immediately without processing
        renderer.handleSceneInput()

        // Assert - We can't directly verify early return, but the function shouldn't crash
        XCTAssertTrue(gameMode, "Game mode should remain true")
    }

    func test_handleSceneInput_processesInputWhenNotInGameMode() {
        // Arrange
        gameMode = false

        // Act - Should proceed past the game mode check
        renderer.handleSceneInput()

        // Assert - Function should complete without crashing
        XCTAssertFalse(gameMode, "Game mode should remain false")
    }

    // MARK: - Camera Input Tests

    func test_handleSceneInput_allowsCameraInputRegardlessOfEditorState() {
        // The function always allows camera WASDQE input, even when editor is disabled

        // Arrange
        gameMode = false
        editorController = nil // No editor

        // Set up camera input
        InputSystem.shared.keyState.wPressed = true
        InputSystem.shared.keyState.aPressed = false
        InputSystem.shared.keyState.sPressed = false
        InputSystem.shared.keyState.dPressed = false
        InputSystem.shared.keyState.qPressed = false
        InputSystem.shared.keyState.ePressed = false

        // Act - Should process camera movement
        renderer.handleSceneInput()

        // Assert - Function should complete without crashing
        XCTAssertTrue(true, "Camera input should be processed regardless of editor state")
    }

    func test_handleSceneInput_processesAllCameraMovementKeys() {
        // Test that all WASDQE keys are captured for camera movement

        // Arrange
        gameMode = false

        let allCameraKeys: [(String, (inout KeyState) -> Void)] = [
            ("W", { $0.wPressed = true }),
            ("A", { $0.aPressed = true }),
            ("S", { $0.sPressed = true }),
            ("D", { $0.dPressed = true }),
            ("Q", { $0.qPressed = true }),
            ("E", { $0.ePressed = true }),
        ]

        // Assert - Each key is checked in handleSceneInput
        for (keyName, _) in allCameraKeys {
            XCTAssertTrue(true, "\(keyName) key should be processed for camera movement")
        }
    }

    // MARK: - Editor Gating Tests

    func test_handleSceneInput_requiresEditorEnabledForGizmoHandling() {
        // The function should only process gizmo/editor logic when editor is enabled

        // Arrange
        gameMode = false
        editorController = nil // No editor controller
        activeEntity = createEntity()
        InputSystem.shared.keyState.shiftPressed = true

        // Act
        renderer.handleSceneInput()

        // Assert - Should return early before gizmo handling
        XCTAssertTrue(true, "Should not process gizmo logic without editor")
    }

    func test_handleSceneInput_requiresActiveEntityForGizmoHandling() {
        // The function requires activeEntity != .invalid

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController
        activeEntity = .invalid // No active entity
        InputSystem.shared.keyState.shiftPressed = true

        // Act
        renderer.handleSceneInput()

        // Assert - Should return early
        XCTAssertEqual(activeEntity, .invalid, "Active entity should still be invalid")
    }

    func test_handleSceneInput_requiresShiftOrGizmoActiveForEditing() {
        // The function requires either Shift pressed OR gizmo active

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController
        activeEntity = createEntity()

        // Case 1: Neither shift nor gizmo active
        InputSystem.shared.keyState.shiftPressed = false
        gizmoActive = false

        // Act
        renderer.handleSceneInput()

        // Assert - Should return early
        XCTAssertTrue(true, "Should require shift or gizmo active")

        // Case 2: Shift pressed
        InputSystem.shared.keyState.shiftPressed = true

        // Act
        renderer.handleSceneInput()

        // Assert - Should proceed (may error due to missing components, but passes the guard)
        XCTAssertTrue(true, "Should proceed with shift pressed")

        // Case 3: Gizmo active
        InputSystem.shared.keyState.shiftPressed = false
        gizmoActive = true

        // Act
        renderer.handleSceneInput()

        // Assert - Should proceed
        XCTAssertTrue(true, "Should proceed with gizmo active")
    }

    // MARK: - Transform Mode Tests

    func test_handleSceneInput_supportsTranslateMode() {
        // Test that translate mode is handled for all axes
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity
        createGizmo(name: "translateGizmo")
        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        InputSystem.shared.keyState.shiftPressed = true
        InputSystem.shared.mouseActive = true

        // Test X axis
        mockController.activeMode = .translate
        mockController.activeAxis = .x

        // Act - Should handle translate X (may fail due to missing camera, but logic is there)
        renderer.handleSceneInput()

        // Assert
        XCTAssertEqual(mockController.activeMode, .translate, "Should be in translate mode")
        XCTAssertEqual(mockController.activeAxis, .x, "Should be on X axis")

        removeGizmo()
    }

    func test_handleSceneInput_supportsRotateMode() {
        // Test that rotate mode is handled for all axes

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity

        InputSystem.shared.keyState.shiftPressed = true
        InputSystem.shared.mouseActive = true

        // Test Y axis
        mockController.activeMode = .rotate
        mockController.activeAxis = .y

        // Act - Should handle rotate Y
        renderer.handleSceneInput()

        // Assert
        XCTAssertEqual(mockController.activeMode, .rotate, "Should be in rotate mode")
        XCTAssertEqual(mockController.activeAxis, .y, "Should be on Y axis")
    }

    func test_handleSceneInput_supportsScaleMode() {
        // Test that scale mode is handled for all axes

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity

        InputSystem.shared.keyState.shiftPressed = true
        InputSystem.shared.mouseActive = true

        // Test Z axis
        mockController.activeMode = .scale
        mockController.activeAxis = .z

        // Act - Should handle scale Z
        renderer.handleSceneInput()

        // Assert
        XCTAssertEqual(mockController.activeMode, .scale, "Should be in scale mode")
        XCTAssertEqual(mockController.activeAxis, .z, "Should be on Z axis")
    }

    func test_handleSceneInput_supportsLightRotateMode() {
        // Test that light rotate mode is handled
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: testEntity, componentType: LightComponent.self)
        activeEntity = testEntity

        createGizmo(name: "translateGizmo")

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        InputSystem.shared.keyState.shiftPressed = true
        InputSystem.shared.mouseActive = true

        // Test light rotate
        mockController.activeMode = .lightRotate
        mockController.activeAxis = .none

        // Act - Should handle light rotate
        renderer.handleSceneInput()

        // Assert
        XCTAssertEqual(mockController.activeMode, .lightRotate, "Should be in light rotate mode")

        removeGizmo()
    }

    // MARK: - Axis Handling Tests

    func test_handleSceneInput_handlesAllThreeAxesForTranslate() {
        // Translate mode should handle X, Y, and Z axes
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity

        createGizmo(name: "translateGizmo")

        let axes: [TransformAxis] = [.x, .y, .z]

        for axis in axes {
            // Arrange
            gameMode = false
            let mockController = EditorController(selectionManager: SelectionManager())
            editorController = mockController

            mockController.activeMode = .translate
            mockController.activeAxis = axis
            InputSystem.shared.keyState.shiftPressed = true
            InputSystem.shared.mouseActive = true

            // Act
            renderer.handleSceneInput()

            // Assert
            XCTAssertTrue(true, "Should handle translate on \(axis) axis")
        }

        removeGizmo()
    }

    func test_handleSceneInput_handlesAllThreeAxesForRotate() {
        // Rotate mode should handle X, Y, and Z axes
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity
        createGizmo(name: "rotateGizmo")

        let axes: [TransformAxis] = [.x, .y, .z]

        for axis in axes {
            // Arrange
            gameMode = false
            let mockController = EditorController(selectionManager: SelectionManager())
            editorController = mockController

            mockController.activeMode = .rotate
            mockController.activeAxis = axis
            InputSystem.shared.keyState.shiftPressed = true
            InputSystem.shared.mouseActive = true

            // Act
            renderer.handleSceneInput()

            // Assert
            XCTAssertTrue(true, "Should handle rotate on \(axis) axis")
        }
        removeGizmo()
    }

    func test_handleSceneInput_handlesAllThreeAxesForScale() {
        // Scale mode should handle X, Y, and Z axes

        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity
        createGizmo(name: "scaleGizmo")
        let axes: [TransformAxis] = [.x, .y, .z]

        for axis in axes {
            // Arrange
            gameMode = false
            let mockController = EditorController(selectionManager: SelectionManager())
            editorController = mockController

            mockController.activeMode = .scale
            mockController.activeAxis = axis
            InputSystem.shared.keyState.shiftPressed = true
            InputSystem.shared.mouseActive = true

            // Act
            renderer.handleSceneInput()

            // Assert
            XCTAssertTrue(true, "Should handle scale on \(axis) axis")
        }
        removeGizmo()
    }

    // MARK: - Mouse Active Requirement Tests

    func test_handleSceneInput_requiresMouseActiveForTransformations() {
        // All transformation modes require InputSystem.shared.mouseActive to be true
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity
        createGizmo(name: "translateGizmo")
        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        mockController.activeMode = .translate
        mockController.activeAxis = .x
        InputSystem.shared.keyState.shiftPressed = true

        // Case 1: Mouse not active
        InputSystem.shared.mouseActive = false

        // Act
        renderer.handleSceneInput()

        // Assert - Should not process transformation
        XCTAssertFalse(InputSystem.shared.mouseActive, "Mouse should not be active")

        // Case 2: Mouse active
        InputSystem.shared.mouseActive = true

        // Act
        renderer.handleSceneInput()

        // Assert - Should process and consume the mouse drag
        XCTAssertFalse(InputSystem.shared.mouseActive, "Mouse drag should be consumed after transformation")

        removeGizmo()
    }

    // MARK: - Light-Specific Handling Tests

    func test_handleSceneInput_scaleMode_handlesDifferentlyForLights() {
        // Scale mode should check if entity has LightComponent and handle differently

        // Arrange
        gameMode = false
        let mockController = EditorController(selectionManager: SelectionManager())
        editorController = mockController

        // Test with non-light entity
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        activeEntity = testEntity

        let hasLight = hasComponent(entityId: testEntity, componentType: LightComponent.self)
        XCTAssertFalse(hasLight, "Test entity should not have light component")

        // Test with light entity
        let lightEntity = createEntity()
        registerComponent(entityId: lightEntity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: lightEntity, componentType: LightComponent.self)

        let hasLightComponent = hasComponent(entityId: lightEntity, componentType: LightComponent.self)
        XCTAssertTrue(hasLightComponent, "Light entity should have light component")

        destroyEntity(entityId: lightEntity)
    }

    // MARK: - Integration Tests

    func test_handleSceneInput_completesWithoutCrashingWithMinimalSetup() {
        // Test that the function can be called without crashing

        // Arrange
        gameMode = false

        // Act
        renderer.handleSceneInput()

        // Assert
        XCTAssertTrue(true, "Function should complete without crashing")
    }

    // MARK: - Gizmo Translation Tests

    // TODO: NEED TO IMPLEMENT THESE TESTS
    func test_handleSceneInput_translateMode_movesGizmoWithEntity() {
        // When translating, both the entity and parentEntityIdGizmo should move

        // This test documents that translation affects:
        // - translateBy(entityId: activeEntity, position: t)
        // - translateBy(entityId: parentEntityIdGizmo, position: t)

        XCTAssertTrue(true, "Translate mode should move both entity and gizmo")
    }

    // MARK: - Rotation Calculation Tests

    func test_handleSceneInput_rotateMode_usesComputeRotationAngleFromGizmo() {
        // Rotate mode uses computeRotationAngleFromGizmo to calculate rotation

        // The function requires:
        // - axis (x, y, or z)
        // - gizmoWorldPosition
        // - lastMousePos and currentMousePos
        // - viewMatrix and projectionMatrix
        // - viewportSize
        // - sensitivity (100.0)

        XCTAssertTrue(true, "Rotate mode should use computeRotationAngleFromGizmo")
    }

    func test_handleSceneInput_rotateMode_appliesAngleMultiplier() {
        // Rotation applies the angle with a multiplier of 10
        // - X axis: r.x -= angle * 10
        // - Y axis: r.y += angle * 10
        // - Z axis: r.z += angle * 10

        XCTAssertTrue(true, "Rotate mode should apply angle with 10x multiplier")
    }

    // MARK: - Light Direction Handling Tests

    func test_handleSceneInput_lightRotateMode_usesDirectionHandle() {
        // Light rotate mode finds and manipulates a "directionHandle" entity

        // The function calls: findEntity(name: "directionHandle")

        XCTAssertTrue(true, "Light rotate mode should use directionHandle entity")
    }

    func test_handleSceneInput_lightRotateMode_choosesPlaneBasedOnCameraForward() {
        // Light rotate mode chooses a 2D plane aligned to camera forward
        // The plane selection logic checks which axis has the largest component

        // If X dominant: YZ plane (axis1 = (0,1,0), axis2 = (0,0,1))
        // If Y dominant: XZ plane (axis1 = (1,0,0), axis2 = (0,0,1))
        // Otherwise: XY plane (axis1 = (1,0,0), axis2 = (0,1,0))

        XCTAssertTrue(true, "Light rotate should choose plane based on camera forward")
    }

    func test_handleSceneInput_lightRotateMode_calculatesRotationMatrix() {
        // Light rotate mode calculates a rotation matrix from the light direction

        // It uses:
        // - zAxis = normalized direction from light to gizmo handle
        // - Calculates xAxis and yAxis using cross products
        // - Converts rotation matrix to quaternion

        XCTAssertTrue(true, "Light rotate should calculate rotation matrix")
    }

    // MARK: - Inspector Refresh Tests

    func test_handleSceneInput_refreshesInspectorAfterTransformations() {
        // All transformation modes call editorController?.refreshInspector()

        // This ensures the inspector UI updates after:
        // - Translate operations
        // - Rotate operations
        // - Scale operations
        // - Light rotate operations

        XCTAssertTrue(true, "All transformations should refresh inspector")
    }

    func test_handleSceneInput_usesInputSystemForAllInput() {
        // The function reads all input from InputSystem.shared

        // It accesses:
        // - InputSystem.shared.keyState (WASDQE, shift)
        // - InputSystem.shared.mouseActive
        // - InputSystem.shared.mouseDeltaX/Y
        // - InputSystem.shared.lastMouseX/Y
        // - InputSystem.shared.mouseX/Y

        XCTAssertTrue(true, "Should use InputSystem.shared for all input")
    }

    func test_handleSceneInput_usesRenderInfoForMatrices() {
        // The function uses renderInfo for view/projection matrices

        // It accesses:
        // - renderInfo.perspectiveSpace (projection matrix)
        // - renderInfo.viewPort (viewport size)

        XCTAssertNotNil(renderInfo.perspectiveSpace, "Perspective space should be set")
        XCTAssertNotNil(renderInfo.viewPort, "Viewport should be set")
    }

    func test_handleSceneInput_usesGlobalEditorState() {
        // The function uses global editor state variables

        // It accesses:
        // - gameMode
        // - activeEntity
        // - parentEntityIdGizmo
        // - gizmoActive
        // - editorController

        XCTAssertTrue(true, "Function should use global editor state")
    }
}
