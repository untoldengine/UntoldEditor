//
//  GizmoSystemTest.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import XCTest

import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine

final class GizmoSystemTests: XCTestCase {
    private var originalActiveEntity: EntityID!
    private var originalParentGizmo: EntityID!
    private var originalGizmoActive: Bool!
    private var originalActiveHitGizmoEntity: EntityID!

    #if canImport(AppKit)
        // Editor controller mock up
        final class TestEditorController {
            enum Axis { case x, y, z, none }
            enum Mode { case translate, rotate, scale, lightRotate, none }
            var activeAxis: Axis = .none
            var activeMode: Mode = .none
        }
    #endif

    override func setUp() {
        super.setUp()
        originalActiveEntity = activeEntity
        originalParentGizmo = parentEntityIdGizmo
        originalGizmoActive = gizmoActive
        originalActiveHitGizmoEntity = activeHitGizmoEntity

        // Put engine in a clean state
        activeEntity = .invalid
        parentEntityIdGizmo = .invalid
        gizmoActive = false
        activeHitGizmoEntity = .invalid

        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Metal device is not available.")
            return
        }

        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        let sharedSelectionManager = SelectionManager()
        editorController = EditorController(selectionManager: sharedSelectionManager)
    }

    override func tearDown() {
        if parentEntityIdGizmo != .invalid {
            removeGizmo()
        }
        activeEntity = originalActiveEntity
        parentEntityIdGizmo = originalParentGizmo
        gizmoActive = originalGizmoActive
        activeHitGizmoEntity = originalActiveHitGizmoEntity

        super.tearDown()
    }

    // MARK: - Helpers

    private func makeEntity(name: String? = nil,
                            pos: SIMD3<Float>? = nil,
                            isLight: Bool = false) -> EntityID
    {
        let e = createEntity()
        if let name { setEntityName(entityId: e, name: name) }
        if let p = pos { translateTo(entityId: e, position: p) }
        if isLight { registerComponent(entityId: e, componentType: LightComponent.self) }
        return e
    }

    // MARK: - createGizmo()

    func test_createGizmo_noActiveEntity_doesNothing() {
        activeEntity = .invalid
        createGizmo(name: "translateGizmo")

        XCTAssertEqual(parentEntityIdGizmo, .invalid, "No gizmo should be created without an active entity.")
        XCTAssertFalse(gizmoActive, "gizmoActive should remain false.")
    }

    func test_createGizmo_createsParentAndActivatesAtActiveEntityPosition() {
        // Arrange: active entity at a known spot
        let active = makeEntity(name: "Cube", pos: SIMD3<Float>(1, 2, 3))
        activeEntity = active

        // Act
        createGizmo(name: "translateGizmo")

        // Assert
        XCTAssertNotEqual(parentEntityIdGizmo, .invalid, "Gizmo parent should be created.")
        XCTAssertTrue(gizmoActive, "gizmoActive should be true after creation.")

        // Must have these components
        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: GizmoComponent.self),
                      "Gizmo parent must have GizmoComponent.")

        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: LocalTransformComponent.self),
                      "Gizmo parent must have Transform.")
        XCTAssertTrue(hasComponent(entityId: parentEntityIdGizmo, componentType: ScenegraphComponent.self),
                      "Gizmo parent must have SceneGraph.")

        // Position should match active entity
        XCTAssertEqual(getPosition(entityId: parentEntityIdGizmo),
                       getPosition(entityId: active),
                       "Gizmo should be placed at active entity’s position.")
    }

    func test_createGizmo_overridesNameForLightEntities() {
        let light = makeEntity(name: "KeyLight", pos: SIMD3<Float>(0, 0, 0), isLight: true)
        activeEntity = light

        // Passing any name; LightComponent should force "translateGizmo_light" internally.
        createGizmo(name: "translateGizmo")

        XCTAssertNotEqual(parentEntityIdGizmo, .invalid, "Gizmo should be created for lights too.")
        XCTAssertTrue(gizmoActive)
    }

    // MARK: - hitGizmoToolAxis()

    func test_hitGizmoToolAxis_validNamesReturnTrue_andInvalidReturnsFalse() {
        let validNames = [
            "xAxisTranslate", "yAxisTranslate", "zAxisTranslate",
            "xAxisRotate", "yAxisRotate", "zAxisRotate",
            "xAxisScale", "yAxisScale", "zAxisScale",
            "directionHandle",
        ]
        for n in validNames {
            let e = makeEntity(name: n)
            XCTAssertTrue(hitGizmoToolAxis(entityId: e), "Expected \(n) to be recognized as a gizmo handle.")
        }

        let invalid = makeEntity(name: "randomNode")
        XCTAssertFalse(hitGizmoToolAxis(entityId: invalid), "Non-gizmo nodes should return false.")
        XCTAssertFalse(hitGizmoToolAxis(entityId: .invalid), "Invalid entity must return false.")
    }

    // MARK: - processGizmoAction()

    #if canImport(AppKit)
        private func makeEditorController() -> EditorController {
            let selectionManager = SelectionManager()
            return EditorController(selectionManager: selectionManager)
        }

        func test_processGizmoAction_setsAxisAndModeForKnownHandles() {
            // Use the real controller type
            let controller = makeEditorController()
            editorController = controller

            // (name → expected axis, expected mode)
            let cases: [(String, TransformAxis, TransformManipulationMode)] = [
                ("xAxisTranslate", .x, .translate),
                ("yAxisTranslate", .y, .translate),
                ("zAxisTranslate", .z, .translate),
                ("xAxisRotate", .x, .rotate),
                ("yAxisRotate", .y, .rotate),
                ("zAxisRotate", .z, .rotate),
                ("xAxisScale", .x, .scale),
                ("yAxisScale", .y, .scale),
                ("zAxisScale", .z, .scale),
                ("directionHandle", .none, .lightRotate),
            ]

            for (name, expAxis, expMode) in cases {
                let e = makeEntity(name: name)
                processGizmoAction(entityId: e)

                XCTAssertEqual(controller.activeAxis, expAxis, "Axis for \(name) incorrect.")
                XCTAssertEqual(controller.activeMode, expMode, "Mode for \(name) incorrect.")
            }

            // Unknown handle → reset to none
            let unknown = makeEntity(name: "notAGizmoPart")
            processGizmoAction(entityId: unknown)
            XCTAssertEqual(controller.activeAxis, .none)
            XCTAssertEqual(controller.activeMode, .none)
        }

        func test_processGizmoAction_earlyReturnOnInvalid() {
            // Arrange
            let controller = EditorController(selectionManager: SelectionManager())
            editorController = controller

            // Seed with values that should remain unchanged
            controller.activeAxis = .x
            controller.activeMode = .translate

            // Act
            processGizmoAction(entityId: .invalid)

            // Assert
            XCTAssertEqual(controller.activeAxis, .x, "Should not modify axis when entity is invalid.")
            XCTAssertEqual(controller.activeMode, .translate, "Should not modify mode when entity is invalid.")
        }
    #endif

    // MARK: - removeGizmo()

    func test_removeGizmo_destroysAndResets() {
        // Create an active entity and then a gizmo
        let active = makeEntity(name: "Box", pos: SIMD3<Float>(0, 0, 0))
        activeEntity = active
        createGizmo(name: "translateGizmo")

        let gizmoParent = parentEntityIdGizmo
        XCTAssertNotEqual(gizmoParent, .invalid)

        // Act
        removeGizmo()

        // Assert: back to defaults and parent entity gone
        XCTAssertEqual(parentEntityIdGizmo, .invalid)
        XCTAssertFalse(gizmoActive)
    }
}
