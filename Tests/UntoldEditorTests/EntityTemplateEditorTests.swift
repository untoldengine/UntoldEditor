//
//  EntityTemplateEditorTests.swift
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

/// Editor-only representation, tinted by one of its values.
final class ProbeMarker: CodeComponent {
    @UntoldAttribute var warm = false

    override var editorRepresentation: EditorRepresentation {
        .icon(systemImage: "flag.fill", tint: warm ? SIMD3<Float>(1, 0.4, 0.2) : SIMD3<Float>(0.2, 0.6, 1))
    }
}

/// No representation.
final class ProbeRules: CodeComponent {
    @UntoldAttribute var limit: Int = 3
}

/// Part of the Probe Ring kind: never offered for another entity, never removed from its own.
final class ProbeRingShape: CodeComponent {
    @UntoldAttribute var radius: Float = 1

    override class var attachment: ComponentAttachment {
        .entityKindOnly
    }
}

final class ProbeRingEntity: EntityTemplate {
    override class var shelf: UntoldEntityShelf {
        .primitives
    }

    override func build(_ entity: EntityID) {
        add(ProbeRingShape.self, to: entity)
    }
}

final class ProbeMarkerEntity: EntityTemplate {
    override class var systemImage: String {
        "flag"
    }

    override func build(_ entity: EntityID) {
        add(ProbeMarker.self, to: entity)
    }
}

final class ProbeShapeEntity: EntityTemplate {
    override class var displayName: String {
        "Probe Ring"
    }

    override class var shelf: UntoldEntityShelf {
        .primitives
    }

    override func build(_ entity: EntityID) {
        add(ProbeRules.self, to: entity)
    }
}

// MARK: - Tests

final class EntityTemplateEditorTests: XCTestCase {
    private var selectionManager: SelectionManager!
    private var sceneGraphModel: SceneGraphModel!

    override func setUp() {
        super.setUp()
        scene = Scene()
        selectionManager = SelectionManager()
        sceneGraphModel = SceneGraphModel()
        CodeComponentRegistry.shared.removeAll()
        EntityTemplateRegistry.shared.removeAll()
        CodeComponentSystem.install()
    }

    override func tearDown() {
        CodeComponentRegistry.shared.removeAll()
        EntityTemplateRegistry.shared.removeAll()
        sceneGraphModel = nil
        selectionManager = nil
        scene = Scene()
        super.tearDown()
    }

    // MARK: Drag payload

    func test_templatePayloadRoundTripsAndSharesThePasteboardType() throws {
        let payload = EntityTemplateDragPayload(entityTemplate: "TorusEntity")
        XCTAssertEqual(try EntityTemplateDragPayload.decode(payload.encoded()), payload)
        XCTAssertEqual(EntityTemplateDragPayload.contentType, AssetDragPayload.contentType)
    }

    func test_templatePayloadIsNeverMistakenForAnotherRowKind() throws {
        let templateData = try EntityTemplateDragPayload(entityTemplate: "TorusEntity").encoded()
        XCTAssertNil(try? LightDragPayload.decode(templateData))
        XCTAssertNil(try? PrimitiveDragPayload.decode(templateData))
        XCTAssertNil(try? AssetDragPayload.decode(templateData))

        let primitiveData = try PrimitiveDragPayload(primitiveType: .cube).encoded()
        let lightData = try LightDragPayload(lightType: PlaceableLightType.allCases[0]).encoded()
        XCTAssertNil(try? EntityTemplateDragPayload.decode(primitiveData))
        XCTAssertNil(try? EntityTemplateDragPayload.decode(lightData))
    }

    // MARK: Shelves

    func test_shelfItemsFollowTheRegistry() {
        XCTAssertTrue(EntityTemplateShelfItem.items(on: .entities).isEmpty)

        EntityTemplateRegistry.shared.register(ProbeMarkerEntity.self, revision: 1)
        EntityTemplateRegistry.shared.register(ProbeShapeEntity.self, revision: 1)

        XCTAssertEqual(
            EntityTemplateShelfItem.items(on: .entities),
            [EntityTemplateShelfItem(typeName: "ProbeMarkerEntity", displayName: "Probe Marker", systemImage: "flag")]
        )
        XCTAssertEqual(EntityTemplateShelfItem.items(on: .primitives).map(\.displayName), ["Probe Ring"])
        XCTAssertTrue(EntityTemplateShelfItem.items(on: .lights).isEmpty)

        EntityTemplateRegistry.shared.unregister(name: "ProbeMarkerEntity")
        XCTAssertTrue(EntityTemplateShelfItem.items(on: .entities).isEmpty, "an unloaded template leaves its shelf")
    }

    // MARK: Placement

    func test_placingATemplateCreatesSelectsAndReportsTheEntity() throws {
        EntityTemplateRegistry.shared.register(ProbeMarkerEntity.self)

        let placement = try XCTUnwrap(placeEntityTemplate(
            "ProbeMarkerEntity",
            at: simd_float3(2, 0, -3),
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager
        ))

        XCTAssertEqual(selectionManager.selectedEntity, placement.entityId)
        XCTAssertEqual(getEntityName(entityId: placement.entityId), placement.entityName)
        XCTAssertEqual(getLocalPosition(entityId: placement.entityId), simd_float3(2, 0, -3))
        XCTAssertEqual(CodeComponentSystem.shared.slots(on: placement.entityId).map(\.typeName), ["ProbeMarker"])
        XCTAssertEqual(placement.statusMessage, "Added Probe Marker: \(placement.entityName)")
        XCTAssertFalse(placement.isError)
    }

    func test_placingAnUnloadedTemplateCreatesNothing() {
        let before = getAllGameEntities().count
        let selectionBefore = selectionManager.selectedEntity
        XCTAssertNil(placeEntityTemplate("Gone", sceneGraphModel: sceneGraphModel, selectionManager: selectionManager))
        XCTAssertEqual(getAllGameEntities().count, before)
        XCTAssertEqual(selectionManager.selectedEntity, selectionBefore, "the selection is left alone")
    }

    // MARK: One Add Component menu

    func test_addableCodeComponentsAreTheLoadedTypesTheEntityLacks() {
        CodeComponentRegistry.shared.register(ProbeMarker.self)
        CodeComponentRegistry.shared.register(ProbeRules.self)
        let entity = createEntity()

        XCTAssertEqual(CodeComponentInspectorView.addableTypes(for: entity).map(\.name), ["ProbeMarker", "ProbeRules"])
        XCTAssertFalse(CodeComponentInspectorView.isAvailable(for: entity), "nothing to draw until the entity carries one")

        CodeComponentInspectorView.add("ProbeRules", to: entity)

        XCTAssertEqual(CodeComponentInspectorView.addableTypes(for: entity).map(\.name), ["ProbeMarker"])
        XCTAssertTrue(CodeComponentInspectorView.isAvailable(for: entity))
        XCTAssertEqual(AddComponentMenu.codeSectionTitle, "From Code")
    }

    // MARK: Components that belong to their kind of entity

    func test_aKindOnlyComponentIsNeverOfferedForAnotherEntity() throws {
        CodeComponentRegistry.shared.register(ProbeRules.self)
        CodeComponentRegistry.shared.register(ProbeRingShape.self)
        let cube = createEntity()

        XCTAssertEqual(
            CodeComponentInspectorView.addableTypes(for: cube).map(\.name), ["ProbeRules"],
            "a ring's shape means nothing on another entity, so Add Component leaves it out"
        )

        // The kind's own template is how it gets onto an entity.
        EntityTemplateRegistry.shared.register(ProbeRingEntity.self)
        let ring = try XCTUnwrap(EntityTemplateRegistry.shared.instantiate("ProbeRingEntity"))
        XCTAssertEqual(CodeComponentSystem.shared.slots(on: ring).map(\.typeName), ["ProbeRingShape"])
        XCTAssertEqual(CodeComponentInspectorView.addableTypes(for: ring).map(\.name), ["ProbeRules"], "a ring still takes ordinary components")
    }

    func test_aKindOnlyComponentCannotBeRemovedButALeftoverSlotCan() throws {
        EntityTemplateRegistry.shared.register(ProbeRingEntity.self)
        let ring = try XCTUnwrap(EntityTemplateRegistry.shared.instantiate("ProbeRingEntity"))
        CodeComponentRegistry.shared.register(ProbeRules.self)
        CodeComponentInspectorView.add("ProbeRules", to: ring)

        XCTAssertFalse(CodeComponentInspectorView.canRemove("ProbeRingShape", from: ring), "it goes when the entity does")
        XCTAssertTrue(CodeComponentInspectorView.canRemove("ProbeRules", from: ring))

        // A slot whose type is no longer loaded has no rule to read; it can be cleaned up.
        CodeComponentSystem.shared.add("TypeFromAnUnloadedLibrary", to: ring)
        XCTAssertTrue(CodeComponentInspectorView.canRemove("TypeFromAnUnloadedLibrary", from: ring))
    }

    func test_aMeshBuiltByAComponentIsNotRemovedOnItsOwn() throws {
        EntityTemplateRegistry.shared.register(ProbeRingEntity.self)
        let ring = try XCTUnwrap(EntityTemplateRegistry.shared.instantiate("ProbeRingEntity"))
        registerComponent(entityId: ring, componentType: RenderComponent.self)
        let plain = createEntity()
        registerComponent(entityId: plain, componentType: RenderComponent.self)

        XCTAssertFalse(CodeComponentInspectorView.generatedMeshIsOwned(on: ring))

        // What setGeneratedMesh records once the component has built the entity's mesh.
        let shape = try XCTUnwrap(CodeComponentRegistry.component(ProbeRingShape.self, on: ring))
        shape.ownsGeneratedMesh = true

        XCTAssertTrue(CodeComponentInspectorView.generatedMeshIsOwned(on: ring))
        XCTAssertFalse(CodeComponentInspectorView.generatedMeshIsOwned(on: plain), "other entities are unaffected")
        // Holds in either authoring mode; scene-composition mode, the shipping default, already
        // refuses every engine component removal.
        XCTAssertFalse(canRemoveComponentFromInspector(componentType: RenderComponent.self, from: ring), "the ring is the component's doing")
    }

    // MARK: Editor-only representation

    func test_markersAreForEntitiesWithNothingElseToShow() throws {
        EntityTemplateRegistry.shared.register(ProbeMarkerEntity.self)
        EntityTemplateRegistry.shared.register(ProbeShapeEntity.self)
        let marked = try XCTUnwrap(EntityTemplateRegistry.shared.instantiate("ProbeMarkerEntity"))
        let plain = try XCTUnwrap(EntityTemplateRegistry.shared.instantiate("ProbeShapeEntity"))

        XCTAssertEqual(
            EditorRepresentationRenderer.markers(),
            [EditorRepresentationRenderer.Marker(entityId: marked, systemImage: "flag.fill", tint: SIMD3<Float>(0.2, 0.6, 1))]
        )
        XCTAssertNil(EditorRepresentationRenderer.marker(for: plain))

        // The marker follows the component's values.
        let component = try XCTUnwrap(CodeComponentSystem.shared.component(named: "ProbeMarker", on: marked) as? ProbeMarker)
        component.warm = true
        XCTAssertEqual(EditorRepresentationRenderer.marker(for: marked)?.tint, SIMD3<Float>(1, 0.4, 0.2))

        // A light already has the editor's own marker.
        registerComponent(entityId: marked, componentType: LightComponent.self)
        XCTAssertTrue(EditorRepresentationRenderer.markers().isEmpty)
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

    func test_anUnknownSymbolFallsBackInsteadOfDrawingNothing() {
        XCTAssertNotNil(EditorRepresentationRenderer.iconPixels(systemImage: "no.such.symbol.anywhere", tint: SIMD3<Float>(1, 1, 1), size: 32))
        XCTAssertNil(EditorRepresentationRenderer.iconPixels(systemImage: "flag.fill", tint: SIMD3<Float>(1, 1, 1), size: 0))
    }
}
