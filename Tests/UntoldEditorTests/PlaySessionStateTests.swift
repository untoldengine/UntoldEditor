//
//  PlaySessionStateTests.swift
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

/// What Play keeps of the scene, whether Stop can put it back in place, and
/// that it does. The scene is saved by the engine's own serializer.
final class PlaySessionStateTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var crate: EntityID = .invalid
    private var lid: EntityID = .invalid
    private var gameCamera: EntityID = .invalid

    override func setUp() {
        super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        scene = Scene()

        crate = makeEntity(named: "Crate", at: simd_float3(2, 0, -1))
        lid = makeEntity(named: "Lid", at: simd_float3(0, 1, 0))
        setParent(childId: lid, parentId: crate)
        rotateTo(entityId: lid, rotation: simd_quatf(angle: .pi / 4, axis: simd_float3(0, 1, 0)))

        gameCamera = createEntity()
        setEntityName(entityId: gameCamera, name: "Game Camera")
        registerComponent(entityId: gameCamera, componentType: CameraComponent.self)
        cameraLookAt(entityId: gameCamera, eye: simd_float3(0, 2, 6), target: .zero, up: simd_float3(0, 1, 0))
    }

    override func tearDown() {
        scene = originalScene
        CameraSystem.shared.activeCamera = originalActiveCamera
        originalScene = nil
        super.tearDown()
    }

    private func makeEntity(named name: String, at position: simd_float3) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        registerTransformComponent(entityId: entity)
        registerSceneGraphComponent(entityId: entity)
        translateTo(entityId: entity, position: position)
        return entity
    }

    private func capture() -> PlaySessionState {
        PlaySessionState.capture(saved: serializeScene())
    }

    private func assertNearlyEqual(_ lhs: simd_float3, _ rhs: simd_float3, accuracy: Float = 0.0001, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(lhs.x, rhs.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.y, rhs.y, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(lhs.z, rhs.z, accuracy: accuracy, file: file, line: line)
    }

    // MARK: - What is taken

    func test_everyEntityOfTheGame_isTaken_withWhereItStands() {
        let state = capture()

        XCTAssertEqual(state.entities, [crate, lid, gameCamera])
        XCTAssertEqual(state.placements[crate]?.position, simd_float3(2, 0, -1))
        XCTAssertEqual(state.placements[lid]?.position, simd_float3(0, 1, 0), "in its parent")
        XCTAssertEqual(state.cameras.keys.map { $0 }, [gameCamera])
        XCTAssertEqual(state.cameras[gameCamera]?.eye, simd_float3(0, 2, 6))
        XCTAssertNotNil(state.fingerprint)
        XCTAssertNil(state.blocker)
    }

    func test_theEditorsCamera_isNotTheScenes() {
        let editorCamera = findSceneCamera()

        let state = capture()

        XCTAssertFalse(state.entities.contains(editorCamera))
        XCTAssertNil(state.cameras[editorCamera])
    }

    // MARK: - Whether the scene has to be loaded again

    func test_aSessionThatMovedNothing_needsNoLoading() {
        let state = capture()

        XCTAssertNil(state.reasonToLoadAgain(saved: serializeScene()))
    }

    func test_aSessionThatMovedThingsAndCameras_needsNoLoading() {
        let state = capture()

        translateTo(entityId: crate, position: simd_float3(9, 9, 9))
        scaleTo(entityId: lid, scale: simd_float3(2, 2, 2))
        cameraLookAt(entityId: gameCamera, eye: simd_float3(5, 5, 5), target: simd_float3(1, 0, 0), up: simd_float3(0, 1, 0))

        XCTAssertNil(state.reasonToLoadAgain(saved: serializeScene()))
    }

    func test_anEntityMore_needsLoading() {
        let state = capture()

        _ = makeEntity(named: "Spawned", at: .zero)

        XCTAssertEqual(state.reasonToLoadAgain(saved: serializeScene()), .entitiesChanged)
    }

    func test_anEntityLess_needsLoading() {
        let state = capture()

        destroyEntity(entityId: lid)
        finalizePendingDestroys()

        XCTAssertEqual(state.reasonToLoadAgain(saved: serializeScene()), .entitiesChanged)
    }

    func test_dataThatChanged_needsLoading() {
        let state = capture()

        setEntityName(entityId: crate, name: "Barrel")

        XCTAssertEqual(state.reasonToLoadAgain(saved: serializeScene()), .dataChanged)
    }

    func test_aSceneWithPhysics_needsLoading_whateverHappened() {
        registerComponent(entityId: crate, componentType: PhysicsComponents.self)
        registerComponent(entityId: crate, componentType: KineticComponent.self)

        let state = capture()

        XCTAssertEqual(state.blocker, .physics)
        XCTAssertEqual(state.reasonToLoadAgain(saved: serializeScene()), .holds(.physics))
    }

    func test_theReasons_readAsSentences() {
        XCTAssertEqual("\(PlaySessionState.ReasonToLoadAgain.holds(.animation))", "an entity is animated")
        XCTAssertEqual("\(PlaySessionState.ReasonToLoadAgain.entitiesChanged)", "entities were added or removed while playing")
        XCTAssertEqual("\(PlaySessionState.ReasonToLoadAgain.dataChanged)", "the scene's data changed while playing")
    }

    // MARK: - Putting it back

    func test_whatMoved_isPutBackWhereItStood() {
        let state = capture()
        let lidWorldBefore = getPosition(entityId: lid)

        translateTo(entityId: crate, position: simd_float3(9, 9, 9))
        rotateTo(entityId: crate, rotation: simd_quatf(angle: 1, axis: simd_float3(1, 0, 0)))
        translateTo(entityId: lid, position: simd_float3(-3, 0, 0))
        scaleTo(entityId: lid, scale: simd_float3(2, 2, 2))

        let restored = state.restoreInPlace()

        XCTAssertEqual(restored, 2)
        XCTAssertEqual(getLocalPosition(entityId: crate), simd_float3(2, 0, -1))
        XCTAssertEqual(getLocalPosition(entityId: lid), simd_float3(0, 1, 0))
        XCTAssertEqual(getScale(entityId: lid), simd_float3(1, 1, 1))
        let turn = getRotationQuaternion(entityId: crate)
        XCTAssertEqual(abs(turn.real), 1, accuracy: 0.0001, "the crate is not turned any more")
        assertNearlyEqual(getPosition(entityId: lid), lidWorldBefore)
    }

    func test_aCameraThatWasSteered_isPutBack() throws {
        let state = capture()
        let before = try XCTUnwrap(CameraPlacement.capture(of: gameCamera))

        // Looked elsewhere, then flown on from there.
        cameraLookAt(entityId: gameCamera, eye: simd_float3(5, 5, 5), target: simd_float3(1, 0, 0), up: simd_float3(0, 1, 0))
        moveCameraWithInput(entityId: gameCamera, input: (w: true, a: false, s: false, d: true, q: false, e: false), speed: 1, deltaTime: 0.5)

        state.restoreInPlace()

        let after = try XCTUnwrap(CameraPlacement.capture(of: gameCamera))
        assertNearlyEqual(after.position, before.position)
        assertNearlyEqual(after.eye, before.eye)
        assertNearlyEqual(after.target, before.target)
        assertNearlyEqual(after.up, before.up)
        // Two turns are the same one when their quaternions are, up to the sign.
        XCTAssertEqual(abs(simd_dot(after.rotation.vector, before.rotation.vector)), 1, accuracy: 0.0001)
    }

    func test_whatStoodStill_isNotTouched() {
        let state = capture()

        XCTAssertEqual(state.restoreInPlace(), 0)
    }

    func test_afterPuttingBack_theSceneSavesAsBefore() throws {
        let before = try JSONEncoder().encode(serializeScene())
        let state = capture()

        translateTo(entityId: crate, position: simd_float3(9, 9, 9))
        cameraLookAt(entityId: gameCamera, eye: simd_float3(5, 5, 5), target: simd_float3(1, 0, 0), up: simd_float3(0, 1, 0))
        state.restoreInPlace()

        let after = try JSONEncoder().encode(serializeScene())
        // Every save gives the entities new identifiers; the rest is the scene.
        let placements = try placementsOnly(of: after)
        XCTAssertEqual(placements, try placementsOnly(of: before))
        XCTAssertEqual(PlaySceneFingerprint.fingerprint(ofSceneJSON: after), PlaySceneFingerprint.fingerprint(ofSceneJSON: before))
    }

    /// Where the entities of a saved scene stand, in their order.
    private func placementsOnly(of json: Data) throws -> [[String]] {
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
        let entities = try XCTUnwrap(root["entities"] as? [[String: Any]])
        return entities.map { entity in
            ["position", "rotation", "scale", "cameraData"].map { key in
                guard let value = entity[key],
                      let data = try? JSONSerialization.data(withJSONObject: ["v": value], options: [.sortedKeys])
                else { return "none" }
                return String(decoding: data, as: UTF8.self)
            }
        }
    }

    // MARK: - A camera's placement

    func test_aCameraThatFlewOnFromItsLookAt_isPutBackWhereItFlewTo() throws {
        cameraLookAt(entityId: gameCamera, eye: simd_float3(0, 2, 6), target: .zero, up: simd_float3(0, 1, 0))
        moveCameraWithInput(entityId: gameCamera, input: (w: true, a: false, s: false, d: false, q: false, e: false), speed: 1, deltaTime: 1)
        let flown = try XCTUnwrap(CameraPlacement.capture(of: gameCamera))
        XCTAssertGreaterThan(simd_length(flown.position - flown.eye), 0.01, "flying leaves the look-at's eye behind")

        cameraLookAt(entityId: gameCamera, eye: simd_float3(8, 8, 8), target: .zero, up: simd_float3(0, 1, 0))
        flown.apply(to: gameCamera)

        let back = try XCTUnwrap(CameraPlacement.capture(of: gameCamera))
        assertNearlyEqual(back.position, flown.position)
        assertNearlyEqual(back.eye, flown.eye)
    }

    func test_anEntityThatIsNoCamera_hasNoPlacementOfOne() {
        XCTAssertNil(CameraPlacement.capture(of: crate))
    }
}
