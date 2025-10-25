//
//  FindSceneCameraTest.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import UntoldEditor
@testable import UntoldEngine
import XCTest

final class FindSceneCameraTests: XCTestCase {
    private var originalScene: Scene!

    override func setUp() {
        super.setUp()
        // 1) Snapshot current scene
        originalScene = scene
        // 2) Inject a fresh, empty scene for isolation
        scene = Scene()
    }

    override func tearDown() {
        // Restore original scene
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Count entities that are both Camera + SceneCamera
    private func sceneCameraCount() -> Int {
        scene.getAllEntities().reduce(into: 0) { count, eid in
            if hasComponent(entityId: eid, componentType: CameraComponent.self),
               hasComponent(entityId: eid, componentType: SceneCameraComponent.self)
            {
                count += 1
            }
        }
    }

    // MARK: - Tests

    func test_returnsExistingSceneCamera_whenPresent() throws {
        // Arrange: create a camera that qualifies as the "scene camera"
        let existing = createEntity()
        registerComponent(entityId: existing, componentType: CameraComponent.self)
        registerComponent(entityId: existing, componentType: SceneCameraComponent.self)
        setEntityName(entityId: existing, name: "Preexisting Scene Camera")

        let beforeCount = sceneCameraCount()

        let found = findSceneCamera()

        // Assert: we got the same entity back and no extra scene camera was created
        XCTAssertEqual(found, existing, "Should return the preexisting scene camera entity.")
        XCTAssertEqual(sceneCameraCount(), beforeCount, "Should not create another scene camera if one exists.")
    }

    func test_createsSceneCamera_whenMissing() throws {
        // Precondition: clean scene has no scene camera
        XCTAssertEqual(sceneCameraCount(), 0, "Fresh scene should not have a scene camera.")

        let created = findSceneCamera()

        // Assert: entity exists, has expected components, and correct name
        XCTAssertTrue(hasComponent(entityId: created, componentType: CameraComponent.self),
                      "Created entity must have CameraComponent.")
        XCTAssertTrue(hasComponent(entityId: created, componentType: SceneCameraComponent.self),
                      "Created entity must have SceneCameraComponent.")

        let name = getEntityName(entityId: created)
        XCTAssertEqual(name, "Scene Camera", "Created scene camera should use the default name.")

        XCTAssertEqual(sceneCameraCount(), 1, "Exactly one scene camera should exist after creation.")

        // Optional: sanity check that look-at was applied.
        // Example (adapt to your API):
        // let pose = getCameraPose(entityId: created)
        // XCTAssertEqual(pose.eye, cameraDefaultEye)
        // XCTAssertEqual(pose.target, cameraTargetDefault)
        // XCTAssertEqual(pose.up, cameraUpDefault)
    }

    func test_idempotent_findSceneCamera_calls() throws {
        let first = findSceneCamera()
        let second = findSceneCamera()

        // Assert: same entity both times, still only one camera
        XCTAssertEqual(first, second, "findSceneCamera() should return the same entity on subsequent calls.")
        XCTAssertEqual(sceneCameraCount(), 1, "Should not create additional scene cameras on repeated calls.")
    }
}
