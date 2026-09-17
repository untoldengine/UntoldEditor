//
//  EntityPluginEditorTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
@testable import UntoldComponentKit
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

// MARK: - Doubles

/// A component: any entity can have it.
final class ProbeRules: ComponentPlugin {
    @UntoldAttribute var limit: Int = 3
}

/// A kind of entity that is only an editor marker, tinted by one of its own properties.
final class ProbeMarkerEntity: EntityPlugin {
    @UntoldAttribute var warm = false

    override class var systemImage: String {
        "flag"
    }

    override var editorRepresentation: EditorRepresentation {
        .icon(systemImage: "flag.fill", tint: warm ? SIMD3<Float>(1, 0.4, 0.2) : SIMD3<Float>(0.2, 0.6, 1))
    }
}

/// A kind of entity with its own properties, geometry to claim, and an editor representation
/// of lines and points that follows the properties.
final class ProbeRingEntity: EntityPlugin {
    @UntoldAttribute("Ring Radius") var radius: Float = 1

    override class var displayName: String {
        "Probe Ring"
    }

    override class var shelf: UntoldEntityShelf {
        .primitives
    }

    /// A new ring starts with the rules on it.
    override func onCreate() {
        add(ProbeRules.self)
    }

    override var editorRepresentation: EditorRepresentation {
        let corners = [SIMD3<Float>(radius, 0, 0), SIMD3<Float>(0, 0, radius), SIMD3<Float>(-radius, 0, 0)]
        return EditorRepresentation([.polyline(corners, closed: true), .points(corners, tint: SIMD3<Float>(1, 1, 0))])
    }
}

/// A kind of entity with nothing to show.
final class ProbePlainEntity: EntityPlugin {}

/// A kind of entity with draggable control points, like the spline in the example.
final class ProbePathEntity: EntityPlugin {
    @UntoldAttribute("Start") var start: SIMD3<Float> = [-1, 0, 0]
    @UntoldAttribute("End") var end: SIMD3<Float> = [1, 0, 0]
    @UntoldAttribute var thickness: Float = 0.1

    var edits: [String] = []

    override func onEditorChanged(property: String) {
        edits.append(property)
    }

    override var editorRepresentation: EditorRepresentation {
        EditorRepresentation([
            .polyline([start, end], closed: false),
            .handles(properties: ["start", "end", "thickness", "missing"], tint: SIMD3<Float>(1, 0.5, 0)),
        ])
    }
}

// MARK: - Tests

final class EntityPluginEditorTests: XCTestCase {
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!

    override func setUp() {
        super.setUp()
        scene = Scene()
        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
        ComponentPluginRegistry.shared.removeAll()
        EntityPluginRegistry.shared.removeAll()
        ScenePluginSystem.install()
    }

    override func tearDown() {
        EditorRepresentationHandles.select(nil)
        activeEntity = .invalid
        EditorUndoManager.shared.clear()
        ComponentPluginRegistry.shared.removeAll()
        EntityPluginRegistry.shared.removeAll()
        sceneGraphModel = nil
        selectionManager = nil
        scene = Scene()
        super.tearDown()
    }

    // MARK: Drag payload

    func test_entityPluginPayloadRoundTripsAndSharesThePasteboardType() throws {
        let payload = EntityPluginDragPayload(entityPlugin: "TorusEntity")
        XCTAssertEqual(try EntityPluginDragPayload.decode(payload.encoded()), payload)
        XCTAssertEqual(EntityPluginDragPayload.contentType, AssetDragPayload.contentType)
    }

    func test_entityPluginPayloadIsNeverMistakenForAnotherRowKind() throws {
        let pluginData = try EntityPluginDragPayload(entityPlugin: "TorusEntity").encoded()
        XCTAssertNil(try? LightDragPayload.decode(pluginData))
        XCTAssertNil(try? PrimitiveDragPayload.decode(pluginData))
        XCTAssertNil(try? AssetDragPayload.decode(pluginData))

        let primitiveData = try PrimitiveDragPayload(primitiveType: .cube).encoded()
        let lightData = try LightDragPayload(lightType: PlaceableLightType.allCases[0]).encoded()
        XCTAssertNil(try? EntityPluginDragPayload.decode(primitiveData))
        XCTAssertNil(try? EntityPluginDragPayload.decode(lightData))
    }

    // MARK: Shelves

    func test_shelfItemsFollowTheRegistry() {
        XCTAssertTrue(EntityPluginShelfItem.items(on: .entities).isEmpty)

        EntityPluginRegistry.shared.register(ProbeMarkerEntity.self, revision: 1)
        EntityPluginRegistry.shared.register(ProbeRingEntity.self, revision: 1)

        XCTAssertEqual(
            EntityPluginShelfItem.items(on: .entities),
            [EntityPluginShelfItem(typeName: "ProbeMarkerEntity", displayName: "Probe Marker", systemImage: "flag")]
        )
        XCTAssertEqual(EntityPluginShelfItem.items(on: .primitives).map(\.displayName), ["Probe Ring"])
        XCTAssertTrue(EntityPluginShelfItem.items(on: .lights).isEmpty)

        EntityPluginRegistry.shared.unregister(name: "ProbeMarkerEntity")
        XCTAssertTrue(EntityPluginShelfItem.items(on: .entities).isEmpty, "an unloaded kind leaves its shelf")
    }

    // MARK: Placement

    func test_placingAnEntityPluginCreatesSelectsAndReportsTheEntity() throws {
        EntityPluginRegistry.shared.register(ProbeRingEntity.self)

        let placement = try XCTUnwrap(placeEntityPlugin(
            "ProbeRingEntity",
            at: simd_float3(2, 0, -3),
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        ))

        XCTAssertEqual(selectionManager.selectedEntity, placement.entityId)
        XCTAssertEqual(getEntityName(entityId: placement.entityId), placement.entityName)
        XCTAssertEqual(getLocalPosition(entityId: placement.entityId), simd_float3(2, 0, -3))
        XCTAssertNotNil(EntityPluginRegistry.plugin(ProbeRingEntity.self, on: placement.entityId), "the entity is of the kind")
        XCTAssertEqual(ScenePluginSystem.shared.slots(on: placement.entityId).map(\.typeName), ["ProbeRules"], "and starts with what onCreate gave it")
        XCTAssertEqual(placement.statusMessage, "Added Probe Ring: \(placement.entityName)")
        XCTAssertFalse(placement.isError)
    }

    func test_placingAnUnloadedKindCreatesNothing() {
        let before = getAllGameEntities().count
        let selectionBefore = selectionManager.selectedEntity
        XCTAssertNil(placeEntityPlugin("Gone", sceneGraphModel: sceneGraphModel, selectionManager: selectionManager))
        XCTAssertEqual(getAllGameEntities().count, before)
        XCTAssertEqual(selectionManager.selectedEntity, selectionBefore, "the selection is left alone")
    }

    // MARK: The Inspector

    func test_everyLoadedComponentIsOfferedAndAKindOfEntityNeverIs() {
        ComponentPluginRegistry.shared.register(ProbeRules.self)
        EntityPluginRegistry.shared.register(ProbeRingEntity.self)
        let cube = createEntity()

        XCTAssertEqual(ScenePluginInspectorView.addableTypes(for: cube).map(\.name), ["ProbeRules"], "a kind of entity is not a component")
        XCTAssertFalse(ScenePluginInspectorView.isAvailable(for: cube), "nothing to draw until the entity carries one")
        XCTAssertFalse(EntityPluginInspectorView.isAvailable(for: cube), "a plain entity has no block of its own")

        ScenePluginInspectorView.add("ProbeRules", to: cube)
        XCTAssertTrue(ScenePluginInspectorView.addableTypes(for: cube).isEmpty)
        XCTAssertTrue(ScenePluginInspectorView.isAvailable(for: cube))
        XCTAssertEqual(AddComponentMenu.codeSectionTitle, "From Code")
    }

    func test_anEntityOfAKindShowsItsOwnPropertiesApartFromItsComponents() throws {
        let ring = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbeRingEntity.self))
        let entity = ring.entity

        XCTAssertTrue(EntityPluginInspectorView.isAvailable(for: entity))
        let slot = try XCTUnwrap(ScenePluginSystem.shared.entitySlot(on: entity))
        XCTAssertEqual(EntityPluginInspectorView.kind(of: slot).title, "Probe Ring")
        XCTAssertEqual(ring.untoldAttributes().map(\.displayLabel), ["Ring Radius"], "the entity's own fields")
        XCTAssertEqual(ScenePluginSystem.shared.slots(on: entity).map(\.typeName), ["ProbeRules"], "its components are listed apart")

        // An edit goes through the same call as a component's, addressed by the kind's type name.
        XCTAssertTrue(ScenePluginSystem.shared.setAttribute("radius", of: "ProbeRingEntity", on: entity, to: .number(2.5)))
        XCTAssertEqual(ring.radius, 2.5)
    }

    func test_aKindThatIsNotLoadedIsNamedByItsTypeAndCanBeCleared() throws {
        let entity = createEntity()
        ScenePluginSystem.shared.setEntityPlugin("KindFromAnUnloadedLibrary", on: entity)

        let slot = try XCTUnwrap(ScenePluginSystem.shared.entitySlot(on: entity))
        XCTAssertFalse(slot.isBound)
        let kind = EntityPluginInspectorView.kind(of: slot)
        XCTAssertEqual(kind.title, "KindFromAnUnloadedLibrary")
        XCTAssertEqual(kind.systemImage, "questionmark.square.dashed")

        XCTAssertTrue(ScenePluginSystem.shared.removeEntityPlugin(from: entity))
        XCTAssertFalse(EntityPluginInspectorView.isAvailable(for: entity))
    }

    func test_aMeshBuiltByTheEntityIsNotRemovedOnItsOwn() throws {
        let ring = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbeRingEntity.self))
        registerComponent(entityId: ring.entity, componentType: RenderComponent.self)
        let plain = createEntity()
        registerComponent(entityId: plain, componentType: RenderComponent.self)

        XCTAssertFalse(EntityPluginInspectorView.generatedMeshIsOwned(on: ring.entity))

        // What setGeneratedMesh records once the plugin has built the entity's mesh.
        ring.ownsGeneratedMesh = true

        XCTAssertTrue(EntityPluginInspectorView.generatedMeshIsOwned(on: ring.entity))
        XCTAssertFalse(EntityPluginInspectorView.generatedMeshIsOwned(on: plain), "other entities are unaffected")
        // Holds in either authoring mode; scene-composition mode, the shipping default, already
        // refuses every engine component removal.
        XCTAssertFalse(canRemoveComponentFromInspector(componentType: RenderComponent.self, from: ring.entity), "the ring is part of the entity")
    }

    // MARK: Editor representation

    func test_drawingsComeFromTheEntityAndFollowItsProperties() throws {
        let marker = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbeMarkerEntity.self))
        let plain = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbePlainEntity.self))
        let bare = createEntity()
        ScenePluginSystem.shared.add(ProbeRules.self, to: bare)

        XCTAssertEqual(
            EditorRepresentationRenderer.drawings(),
            [EditorRepresentationRenderer.Drawing(entityId: marker.entity, representation: .icon(systemImage: "flag.fill", tint: SIMD3<Float>(0.2, 0.6, 1)))]
        )
        XCTAssertNil(EditorRepresentationRenderer.drawing(for: plain.entity), "a kind with nothing to show")
        XCTAssertNil(EditorRepresentationRenderer.drawing(for: bare), "components have no editor representation; entities do")

        marker.warm = true
        XCTAssertEqual(EditorRepresentationRenderer.drawing(for: marker.entity)?.representation, .icon(systemImage: "flag.fill", tint: SIMD3<Float>(1, 0.4, 0.2)))
    }

    func test_anEntityWithGeometryStillGetsItsEditorRepresentation() throws {
        let ring = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbeRingEntity.self))
        registerComponent(entityId: ring.entity, componentType: RenderComponent.self)
        ring.radius = 2

        let items = try XCTUnwrap(EditorRepresentationRenderer.drawing(for: ring.entity)).representation.items
        let corners = [SIMD3<Float>(2, 0, 0), SIMD3<Float>(0, 0, 2), SIMD3<Float>(-2, 0, 0)]
        XCTAssertEqual(items, [.polyline(corners, closed: true), .points(corners, tint: SIMD3<Float>(1, 1, 0))], "geometry in the game, control points in the editor")
    }

    // MARK: Handles

    func test_handlesAreTheEntitysVectorPropertiesInWorldSpace() throws {
        let path = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbePathEntity.self, at: SIMD3<Float>(10, 0, 0)))
        // The transform the editor computes each frame; set it as a rendered frame would.
        registerComponent(entityId: path.entity, componentType: WorldTransformComponent.self)
        scene.get(component: WorldTransformComponent.self, for: path.entity)?.space = matrix4x4Translation(10, 0, 0)

        let placed = EditorRepresentationHandles.placed()
        XCTAssertEqual(placed.map(\.handle.property), ["start", "end"], "a Float and a name that is no property are skipped")
        XCTAssertEqual(placed.map(\.worldPosition), [SIMD3<Float>(9, 0, 0), SIMD3<Float>(11, 0, 0)])
        XCTAssertEqual(placed.first?.tint, SIMD3<Float>(1, 0.5, 0))
        XCTAssertEqual(EditorRepresentationHandles.worldPosition(of: EditorRepresentationHandles.Handle(entityId: path.entity, property: "end")), SIMD3<Float>(11, 0, 0))
        XCTAssertNil(EditorRepresentationHandles.worldPosition(of: EditorRepresentationHandles.Handle(entityId: path.entity, property: "thickness")))
    }

    func test_pickTakesTheHandleNearestTheClickOnScreen() {
        let left = EditorRepresentationHandles.Handle(entityId: 1, property: "a")
        let right = EditorRepresentationHandles.Handle(entityId: 1, property: "b")
        let behind = EditorRepresentationHandles.Handle(entityId: 1, property: "c")
        let candidates = [
            EditorRepresentationHandles.Placed(handle: left, worldPosition: SIMD3<Float>(-1, 0, -5), tint: .one),
            EditorRepresentationHandles.Placed(handle: right, worldPosition: SIMD3<Float>(1, 0, -5), tint: .one),
            EditorRepresentationHandles.Placed(handle: behind, worldPosition: SIMD3<Float>(0, 0, 5), tint: .one),
        ]
        // A camera at the origin looking down -Z, a 90 degree square view of 1000 by 1000 points:
        // x = 1 at depth 5 lands 100 points right of the centre.
        let view = matrix_identity_float4x4
        let projection = matrixPerspectiveRightHand(fovyRadians: .pi / 2, aspectRatio: 1, nearZ: 0.1, farZ: 100)
        let size = CGSize(width: 1000, height: 1000)
        func pick(_ x: CGFloat, _ y: CGFloat) -> EditorRepresentationHandles.Handle? {
            EditorRepresentationHandles.pick(among: candidates, atViewLocation: CGPoint(x: x, y: y), viewSize: size, viewSpace: view, perspectiveSpace: projection)
        }

        XCTAssertEqual(pick(600, 500), right, "dead on")
        XCTAssertEqual(pick(608, 506), right, "within the pick distance")
        XCTAssertEqual(pick(400, 500), left)
        XCTAssertNil(pick(500, 500), "between the two, too far from either")
        XCTAssertNil(pick(500, 900), "nothing there")
        XCTAssertNil(pick(500, 500), "the one behind the camera projects onto the centre only in appearance; it is never picked")
        XCTAssertNil(EditorRepresentationHandles.pick(among: candidates, atViewLocation: CGPoint(x: 600, y: 500), viewSize: .zero, viewSpace: view, perspectiveSpace: projection))
    }

    func test_projectionAgreesWithTheEnginesClickRay() {
        // The same frame the viewport's gesture recognizers report in: what projects to a view
        // location must be on the ray the engine builds from that location. This guards the
        // screen orientation, on which a click landing on a handle depends.
        let eye = SIMD3<Float>(2, 3, 8)
        let view = matrix_look_at_right_hand(eye, SIMD3<Float>(0, 0.5, 0), SIMD3<Float>(0, 1, 0))
        let projection = matrixPerspectiveRightHand(fovyRadians: degreesToRadians(degrees: 65), aspectRatio: 1.6, nearZ: 0.1, farZ: 100)
        let size = CGSize(width: 1600, height: 1000)
        let world = SIMD3<Float>(-0.5, 1.2, 1.0)

        let projected = EditorRepresentationHandles.project(world, viewProjection: projection * view, viewSize: size)!
        let direction = rayDirectionInWorldSpace(
            uMouseLocation: projected,
            uViewPortDim: SIMD2<Float>(Float(size.width), Float(size.height)),
            uPerspectiveSpace: projection,
            uViewSpace: view
        )

        let toPoint = world - eye
        let along = simd_dot(toPoint, simd_normalize(direction))
        let offRay = simd_length(toPoint - along * simd_normalize(direction))
        XCTAssertGreaterThan(along, 0, "in front of the camera")
        XCTAssertLessThan(offRay, 0.001, "the ray through the projected location passes through the point")
    }

    func test_movingAHandleWritesThePropertyInTheEntitysLocalSpace() throws {
        let path = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbePathEntity.self))
        registerComponent(entityId: path.entity, componentType: WorldTransformComponent.self)
        // The entity sits at x = 10, turned a quarter turn about Y: local +X points to world -Z.
        scene.get(component: WorldTransformComponent.self, for: path.entity)?.space =
            matrix4x4Translation(10, 0, 0) * matrix4x4Rotation(radians: .pi / 2, axis: SIMD3<Float>(0, 1, 0))
        let handle = EditorRepresentationHandles.Handle(entityId: path.entity, property: "end")

        XCTAssertTrue(EditorRepresentationHandles.move(handle, toWorld: SIMD3<Float>(10, 2, -3)))

        XCTAssertEqual(path.end.x, 3, accuracy: 1e-4)
        XCTAssertEqual(path.end.y, 2, accuracy: 1e-4)
        XCTAssertEqual(path.end.z, 0, accuracy: 1e-4)
        XCTAssertEqual(path.edits, ["end"], "the entity is told, as after an Inspector edit, so it rebuilds")
        XCTAssertFalse(EditorRepresentationHandles.move(EditorRepresentationHandles.Handle(entityId: path.entity, property: "thickness"), toWorld: .zero), "not a vector")
        XCTAssertFalse(EditorRepresentationHandles.move(EditorRepresentationHandles.Handle(entityId: 999_999, property: "end"), toWorld: .zero), "no such entity")
    }

    func test_theSelectedHandleHoldsOnlyWhileItsEntityIsActive() throws {
        let path = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbePathEntity.self))
        let handle = EditorRepresentationHandles.Handle(entityId: path.entity, property: "start")

        EditorRepresentationHandles.select(handle)
        activeEntity = path.entity
        XCTAssertEqual(EditorRepresentationHandles.active, handle)

        activeEntity = createEntity()
        XCTAssertNil(EditorRepresentationHandles.active, "another entity took the selection")

        activeEntity = path.entity
        XCTAssertEqual(EditorRepresentationHandles.active, handle, "back on the entity, the handle is still the one selected")
        EditorRepresentationHandles.select(nil)
        XCTAssertNil(EditorRepresentationHandles.active)
    }

    func test_aHandleDragIsOneUndoStep() throws {
        let path = try XCTUnwrap(EntityPluginRegistry.shared.instantiate(ProbePathEntity.self))
        let handle = EditorRepresentationHandles.Handle(entityId: path.entity, property: "end")
        EditorRepresentationHandles.select(handle)
        activeEntity = path.entity
        EditorUndoManager.shared.clear()

        EditorRepresentationHandles.dragDidBegin()
        EditorRepresentationHandles.move(handle, toWorld: SIMD3<Float>(2, 0, 0))
        EditorRepresentationHandles.move(handle, toWorld: SIMD3<Float>(3, 0, 0))
        EditorRepresentationHandles.dragDidEnd()

        XCTAssertEqual(path.end, SIMD3<Float>(3, 0, 0))
        XCTAssertTrue(EditorUndoManager.shared.canUndo, "the whole drag is one step")
        EditorUndoManager.shared.undo()
        XCTAssertEqual(path.end, SIMD3<Float>(1, 0, 0), "back to where the drag started, not one move back")
        XCTAssertFalse(EditorUndoManager.shared.canUndo)

        // A drag that ends where it began registers nothing.
        EditorRepresentationHandles.dragDidBegin()
        EditorRepresentationHandles.dragDidEnd()
        XCTAssertFalse(EditorUndoManager.shared.canUndo)
    }

    func test_lineRunsCloseTheLoopAndNeverLeaveAGap() {
        let triangle = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)]

        XCTAssertEqual(EditorRepresentationRenderer.lineRuns(triangle, closed: false).map(\.count), [3])
        let closed = EditorRepresentationRenderer.lineRuns(triangle, closed: true)
        XCTAssertEqual(closed.map(\.count), [4])
        XCTAssertEqual(closed.first?.last, SIMD4<Float>(0, 0, 0, 1), "back to the first point")

        XCTAssertTrue(EditorRepresentationRenderer.lineRuns([SIMD3<Float>(0, 0, 0)], closed: false).isEmpty, "one point is not a line")

        let long = (0 ..< 10).map { SIMD3<Float>(Float($0), 0, 0) }
        let runs = EditorRepresentationRenderer.lineRuns(long, closed: false, maxVerticesPerRun: 4)
        XCTAssertEqual(runs.map(\.count), [4, 4, 4])
        XCTAssertEqual(runs[0].last, runs[1].first, "consecutive runs share a point")
        XCTAssertEqual(runs[2].last, SIMD4<Float>(9, 0, 0, 1))
    }

    func test_iconPixelsAreAnOpaqueDiscOnAClearGround() throws {
        let size = 64
        let pixels = try XCTUnwrap(EditorRepresentationRenderer.iconPixels(systemImage: "flag.fill", tint: SIMD3<Float>(1, 0, 0), size: size))
        XCTAssertEqual(pixels.count, size * size * 4)

        func alpha(_ x: Int, _ y: Int) -> UInt8 {
            pixels[(y * size + x) * 4 + 3]
        }
        XCTAssertEqual(alpha(0, 0), 0, "the corners are outside the disc; the billboard shader discards them")
        XCTAssertEqual(alpha(size - 1, size - 1), 0)
        XCTAssertEqual(alpha(size / 2, size / 2), 255, "the disc is opaque, so the alpha cut keeps it")

        let tinted = stride(from: 0, to: pixels.count, by: 4).contains { pixels[$0] > 200 && pixels[$0 + 1] < 60 && pixels[$0 + 2] < 60 }
        XCTAssertTrue(tinted, "the symbol and ring are drawn in the tint")
    }

    func test_pointPixelsAreASmallTintedDot() throws {
        let size = 64
        let pixels = try XCTUnwrap(EditorRepresentationRenderer.dotPixels(tint: SIMD3<Float>(0, 1, 0), size: size))

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            Array(pixels[(y * size + x) * 4 ..< (y * size + x) * 4 + 4])
        }
        let centre = pixel(size / 2, size / 2)
        XCTAssertEqual(centre[3], 255, "opaque at the centre, so the alpha cut keeps it")
        XCTAssertTrue(centre[1] > 240 && centre[0] < 10 && centre[2] < 10, "in the tint, give or take color matching: \(centre)")
        XCTAssertEqual(pixel(size / 2, 4)[3], 0, "most of the billboard is clear, so a point reads as a point")
        XCTAssertEqual(pixel(0, 0)[3], 0)
        XCTAssertNil(EditorRepresentationRenderer.dotPixels(tint: .one, size: 0))
    }

    func test_anUnknownSymbolFallsBackInsteadOfDrawingNothing() {
        XCTAssertNotNil(EditorRepresentationRenderer.iconPixels(systemImage: "no.such.symbol.anywhere", tint: SIMD3<Float>(1, 1, 1), size: 32))
        XCTAssertNil(EditorRepresentationRenderer.iconPixels(systemImage: "flag.fill", tint: SIMD3<Float>(1, 1, 1), size: 0))
    }
}
