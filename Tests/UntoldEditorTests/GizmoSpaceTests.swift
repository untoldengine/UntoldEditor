//
//  GizmoSpaceTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The gizmo's axes in Local space and the snapping of a rotation drag.
final class GizmoSpaceTests: XCTestCase {
    private var savedSnap: EditorSnapSettings!

    override func setUp() {
        super.setUp()
        scene = Scene()
        activeEntity = .invalid
        savedSnap = gizmoSnapSettings
        gizmoSnapSettings = EditorSnapSettings(defaults: nil)
    }

    override func tearDown() {
        endGizmoDrag()
        gizmoSnapSettings = savedSnap
        super.tearDown()
    }

    private func entity(rotatedBy degrees: Float, about axis: simd_float3, parent: EntityID? = nil) -> EntityID {
        let entity = createEntity()
        registerComponent(entityId: entity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: entity, componentType: WorldTransformComponent.self)
        registerComponent(entityId: entity, componentType: ScenegraphComponent.self)
        if let parent {
            setParent(childId: entity, parentId: parent)
        }
        if degrees != 0 {
            applyGizmoRotationDelta(entityId: entity, axis: axis, degrees: degrees)
        }
        return entity
    }

    private func assertEqual(_ vector: simd_float3, _ expected: simd_float3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(vector.x, expected.x, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(vector.y, expected.y, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(vector.z, expected.z, accuracy: 0.0001, file: file, line: line)
    }

    func test_localAxis_followsTheEntitysRotation_worldAxisDoesNot() {
        let entity = entity(rotatedBy: 90, about: simd_float3(0, 1, 0))
        assertEqual(gizmoAxisDirection(for: .x, entityId: entity, space: .local), simd_float3(0, 0, -1))
        assertEqual(gizmoAxisDirection(for: .y, entityId: entity, space: .local), simd_float3(0, 1, 0))
        assertEqual(gizmoAxisDirection(for: .x, entityId: entity, space: .world), simd_float3(1, 0, 0))
    }

    func test_localAxis_includesTheParentsRotation() {
        let parent = entity(rotatedBy: 90, about: simd_float3(0, 1, 0))
        let child = entity(rotatedBy: 0, about: simd_float3(0, 1, 0), parent: parent)
        assertEqual(gizmoAxisDirection(for: .x, entityId: child, space: .local), simd_float3(0, 0, -1))
    }

    func test_rotationSnap_appliesWholeStepsOfTheAccumulatedTurn() {
        gizmoSnapSettings.isEnabled = true
        gizmoSnapSettings.rotationStep = 15
        beginGizmoRotationDrag()

        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 0, "4° is nearer to 0 than to 15")
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 15, "8° accumulated rounds to the first step")
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 0, "12° stays on it")
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 0, "16° too")
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 8), 15, "24° accumulated rounds to the second")

        endGizmoDrag()
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 4, "No drag, no accumulation")
    }

    func test_rotationSnap_off_passesTheRawDelta() {
        beginGizmoRotationDrag()
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: 4), 4)
        XCTAssertEqual(snappedGizmoRotationDelta(degrees: -2.5), -2.5)
    }
}
