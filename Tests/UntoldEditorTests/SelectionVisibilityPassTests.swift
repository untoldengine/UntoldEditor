//
//  SelectionVisibilityPassTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import MetalKit
import ModelIO
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// Which entities show in a rectangle of the viewport, told by the pass that
/// draws them: real meshes, drawn by the renderer's device and read back.
///
/// The camera stands five units in front of the origin over a viewport of
/// 400 by 300 points and sees a quarter turn from top to bottom: a unit of
/// the world at the origin is 30 points, and the middle is (200, 150),
/// measured from the bottom left.
@MainActor
final class SelectionVisibilityPassTests: XCTestCase {
    private var originalScene: Scene!
    private var originalActiveCamera: EntityID?
    private var originalIgnoresTransparents = false
    private var window: NSWindow!
    private var renderer: UntoldRenderer!
    private var selectionManager: SelectionManager!
    private let size = CGSize(width: 400, height: 300)

    override func setUp() {
        super.setUp()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        guard let created = UntoldRenderer.create() else {
            XCTFail("Failed to initialize the renderer")
            return
        }
        renderer = created
        window.contentView = created.metalView
        created.initResources()

        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalIgnoresTransparents = isIgnoringRayIntersectionWithTransparents()
        scene = Scene()
        setIgnoreRayIntersectionWithTransparents(false)
        selectionManager = SelectionManager()
    }

    override func tearDown() {
        selectionManager = nil
        setIgnoreRayIntersectionWithTransparents(originalIgnoresTransparents)
        gizmoTargets = []
        SelectionHighlights.shared.boxes = []
        CameraSystem.shared.activeCamera = originalActiveCamera
        scene = originalScene
        originalScene = nil
        renderer = nil
        window = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// A cube of `side` with real meshes, as the Entity menu makes one.
    private func makeCube(_ name: String, at position: simd_float3, side: Float = 1) -> EntityID {
        let entity = createEntity()
        setEntityName(entityId: entity, name: name)
        setEntityMeshDirect(entityId: entity, meshes: BasicPrimitives.createCube(extent: side), assetName: name)
        translateTo(entityId: entity, position: position)
        return entity
    }

    private func view(eye: simd_float3 = simd_float3(0, 0, 5), target: simd_float3 = .zero, reverseZ: Bool = false) -> MarqueeGeometry.View {
        let camera = createEntity()
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        cameraLookAt(entityId: camera, eye: eye, target: target, up: simd_float3(0, 1, 0))
        let aspect = Float(size.width / size.height)
        return MarqueeGeometry.View(
            viewSpace: scene.get(component: CameraComponent.self, for: camera)?.viewSpace ?? matrix_identity_float4x4,
            perspectiveSpace: reverseZ
                ? matrixPerspectiveRightHandReverseZ(fovyRadians: .pi / 2, aspectRatio: aspect, nearZ: 0.1, farZ: 100)
                : matrixPerspectiveRightHand(fovyRadians: .pi / 2, aspectRatio: aspect, nearZ: 0.1, farZ: 100),
            size: size
        )
    }

    private func seen(in rect: CGRect, among drawn: [EntityID], view: MarqueeGeometry.View? = nil, scale: CGFloat = 2) -> Set<EntityID>? {
        SelectionVisibilityPass.entitiesSeen(in: rect, view: view ?? self.view(), scale: scale, drawn: drawn)
    }

    /// What the rectangle selects, with the pass telling what is seen.
    private func selected(by rect: CGRect, view: MarqueeGeometry.View? = nil) -> [EntityID] {
        MarqueeSelection.entities(
            inside: rect,
            view: view ?? self.view(),
            selectionManager: selectionManager,
            seen: { rect, view, drawn in
                SelectionVisibilityPass.entitiesSeen(in: rect, view: view, scale: 2, drawn: drawn)
            }
        )
    }

    /// A wall two units each way just in front of the origin, and a small
    /// cube well behind it, wholly covered by it.
    private func makeWallAndWhatIsBehind() -> (wall: EntityID, behind: EntityID) {
        (makeCube("Wall", at: simd_float3(0, 0, 1), side: 2), makeCube("Behind", at: simd_float3(0, 0, -3), side: 0.5))
    }

    private let middle = CGRect(x: 150, y: 100, width: 100, height: 100)

    /// A rectangle that holds the wall, which reaches 50 points from the
    /// middle, with ten points to spare.
    private let aroundTheWall = CGRect(x: 140, y: 90, width: 120, height: 120)

    // MARK: - What is seen

    func test_anEntityIsSeen_inARectangleOverIt_andNotInOneBesideIt() {
        let cube = makeCube("Cube", at: .zero)

        XCTAssertEqual(seen(in: CGRect(x: 190, y: 140, width: 20, height: 20), among: [cube]), [cube])
        XCTAssertEqual(seen(in: CGRect(x: 250, y: 140, width: 20, height: 20), among: [cube]), [])
    }

    func test_whatStandsBehindAnother_isNotSeen() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        XCTAssertEqual(seen(in: middle, among: [wall, behind]), [wall])
        XCTAssertEqual(seen(in: middle, among: [behind, wall]), [wall], "whichever is drawn first")
    }

    func test_alone_whatStoodBehindIsSeen() {
        let (_, behind) = makeWallAndWhatIsBehind()

        XCTAssertEqual(seen(in: middle, among: [behind]), [behind])
    }

    func test_whatShowsBesideAnother_isSeenThere_andNotWhereItIsCovered() {
        let wall = makeCube("Wall", at: simd_float3(0, 0, 1), side: 2)
        // Three units to the right and behind: it shows from 250 to 270
        // points, and from 244 to 250 it is behind the wall, which ends at 250.
        let beside = makeCube("Beside", at: simd_float3(3, 0, -3))

        XCTAssertEqual(seen(in: CGRect(x: 255, y: 140, width: 10, height: 20), among: [wall, beside]), [beside])
        XCTAssertEqual(seen(in: CGRect(x: 245, y: 145, width: 4, height: 10), among: [wall, beside]), [wall])
        XCTAssertEqual(seen(in: CGRect(x: 230, y: 140, width: 40, height: 20), among: [wall, beside]), [wall, beside])
    }

    func test_eachEntity_isToldApart() {
        let left = makeCube("Left", at: simd_float3(-3, 0, 0))
        let middleCube = makeCube("Middle", at: .zero)
        let right = makeCube("Right", at: simd_float3(3, 0, 0))
        let all = [left, middleCube, right]

        XCTAssertEqual(seen(in: CGRect(x: 100, y: 140, width: 20, height: 20), among: all), [left])
        XCTAssertEqual(seen(in: CGRect(x: 190, y: 140, width: 20, height: 20), among: all), [middleCube])
        XCTAssertEqual(seen(in: CGRect(x: 280, y: 140, width: 20, height: 20), among: all), [right])
        XCTAssertEqual(seen(in: CGRect(x: 0, y: 0, width: 400, height: 300), among: all), [left, middleCube, right])
    }

    func test_anEntityIsSeenWhereItWasMovedTurnedAndScaledTo() {
        let cube = makeCube("Cube", at: simd_float3(2, 1, 0))
        rotateTo(entityId: cube, rotation: simd_quatf(angle: .pi / 4, axis: simd_float3(0, 1, 0)))
        scaleTo(entityId: cube, scale: simd_float3(1, 2, 1))

        // Two units right and one up: 60 points right of the middle, 30 above it.
        XCTAssertEqual(seen(in: CGRect(x: 255, y: 175, width: 10, height: 10), among: [cube]), [cube])
        XCTAssertEqual(seen(in: CGRect(x: 258, y: 205, width: 4, height: 4), among: [cube]), [cube], "twice as tall")
        XCTAssertEqual(seen(in: CGRect(x: 195, y: 145, width: 10, height: 10), among: [cube]), [])
    }

    func test_upInTheWorld_isUpInTheRectanglesMeasure() {
        let cube = makeCube("Cube", at: simd_float3(0, 3, 0))

        XCTAssertEqual(seen(in: CGRect(x: 190, y: 230, width: 20, height: 20), among: [cube]), [cube])
        XCTAssertEqual(seen(in: CGRect(x: 190, y: 50, width: 20, height: 20), among: [cube]), [])
    }

    func test_itDoesNotMatterHowTheProjectionKeepsDepth() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        XCTAssertEqual(seen(in: middle, among: [wall, behind], view: view(reverseZ: true)), [wall])
        XCTAssertEqual(seen(in: middle, among: [behind, wall], view: view(reverseZ: true)), [wall])
    }

    func test_fromTheOtherSide_theOtherOneIsSeen() {
        let (wall, behind) = makeWallAndWhatIsBehind()
        let fromBehind = view(eye: simd_float3(0, 0, -8))

        // The small cube is now in front of the wall, and both show.
        XCTAssertEqual(seen(in: CGRect(x: 195, y: 145, width: 10, height: 10), among: [wall, behind], view: fromBehind), [behind])
        XCTAssertEqual(seen(in: middle, among: [wall, behind], view: fromBehind), [wall, behind])
    }

    // MARK: - The rectangle

    func test_aRectangleWithoutASize_seesWhatIsUnderIt() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        XCTAssertEqual(seen(in: CGRect(x: 200, y: 150, width: 0, height: 0), among: [wall, behind]), [wall])
        XCTAssertEqual(seen(in: CGRect(x: 100, y: 150, width: 200, height: 0), among: [wall, behind]), [wall], "a drag straight across")
    }

    func test_aRectangleThatReachesBeyondTheViewport_isCutToIt() {
        let cube = makeCube("Cube", at: .zero)

        XCTAssertEqual(seen(in: CGRect(x: -500, y: -500, width: 1000, height: 1000), among: [cube]), [cube])
    }

    func test_aRectangleOutsideTheViewport_cannotBeTold() {
        let cube = makeCube("Cube", at: .zero)

        XCTAssertNil(seen(in: CGRect(x: 500, y: 400, width: 50, height: 50), among: [cube]))
    }

    func test_withNothingDrawn_nothingIsSeen() {
        XCTAssertEqual(seen(in: middle, among: []), [])
    }

    func test_aCoarserScale_seesTheSame() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        XCTAssertEqual(seen(in: middle, among: [wall, behind], scale: 1), [wall])
        XCTAssertEqual(seen(in: middle, among: [wall, behind], scale: 0.5), [wall])
    }

    // MARK: - The pixels of the rectangle

    func test_thePixels_areCountedFromTheTopOfTheViewport() throws {
        let region = try XCTUnwrap(SelectionVisibilityPass.PixelRegion(
            rect: CGRect(x: 10, y: 20, width: 30, height: 40),
            viewSize: size,
            scale: 2
        ))

        XCTAssertEqual(region.x, 20)
        XCTAssertEqual(region.y, 480, "from 60 up to 20 points above the bottom is 240 to 280 below the top")
        XCTAssertEqual(region.width, 60)
        XCTAssertEqual(region.height, 80)
        XCTAssertEqual(region.viewWidth, 800)
        XCTAssertEqual(region.viewHeight, 600)
    }

    func test_thePixels_stayInTheViewport_andAreNeverNone() throws {
        let beyond = try XCTUnwrap(SelectionVisibilityPass.PixelRegion(rect: CGRect(x: -50, y: -50, width: 1000, height: 1000), viewSize: size, scale: 1))
        XCTAssertEqual(beyond, try XCTUnwrap(SelectionVisibilityPass.PixelRegion(rect: CGRect(origin: .zero, size: size), viewSize: size, scale: 1)))

        let point = try XCTUnwrap(SelectionVisibilityPass.PixelRegion(rect: CGRect(x: 400, y: 0, width: 0, height: 0), viewSize: size, scale: 1))
        XCTAssertEqual(point.width, 1)
        XCTAssertEqual(point.height, 1)
        XCTAssertEqual(point.x, 399)
        XCTAssertEqual(point.y, 299)

        XCTAssertNil(SelectionVisibilityPass.PixelRegion(rect: CGRect(x: 500, y: 0, width: 10, height: 10), viewSize: size, scale: 1))
        XCTAssertNil(SelectionVisibilityPass.PixelRegion(rect: CGRect(x: 0, y: 0, width: 10, height: 10), viewSize: .zero, scale: 1))
        XCTAssertNil(SelectionVisibilityPass.PixelRegion(rect: CGRect(x: 0, y: 0, width: 10, height: 10), viewSize: size, scale: 0))
    }

    func test_aRectangleOfVeryManyPixels_isDrawnCoarser() throws {
        let large = CGSize(width: 4000, height: 3000)
        let region = try XCTUnwrap(SelectionVisibilityPass.PixelRegion(rect: CGRect(origin: .zero, size: large), viewSize: large, scale: 2))

        XCTAssertLessThanOrEqual(CGFloat(region.width * region.height), SelectionVisibilityPass.maximumPixels * 1.01)
        XCTAssertEqual(Double(region.width) / Double(region.height), 4.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(region.viewWidth, region.width)
    }

    func test_theUniforms_areLaidOutAsTheShaderReadsThem() {
        XCTAssertEqual(MemoryLayout<SelectionVisibilityPass.Uniforms>.stride, 80)
        XCTAssertEqual(MemoryLayout<SelectionVisibilityPass.Uniforms>.offset(of: \.identifier), 64)
    }

    // MARK: - What the rectangle selects

    func test_theRectangle_selectsWhatIsSeen_andLeavesOutWhatIsHidden() {
        let (wall, behind) = makeWallAndWhatIsBehind()
        let beside = makeCube("Beside", at: simd_float3(3, 0, -3))

        XCTAssertEqual(selected(by: aroundTheWall), [wall])
        XCTAssertEqual(Set(selected(by: CGRect(x: 0, y: 0, width: 400, height: 300))), [wall, beside])
        XCTAssertFalse(selected(by: CGRect(x: 0, y: 0, width: 400, height: 300)).contains(behind))
    }

    func test_whatIsSeenInTheRectangle_butReachesOutOfIt_isLeftOut() {
        let crate = makeCube("Crate", at: .zero)
        // A floor six units each way under the crate: it shows in the
        // rectangle, below the crate, and reaches far out of it.
        let floor = makeCube("Floor", at: simd_float3(0, -3.5, 0), side: 6)
        let around = CGRect(x: 170, y: 120, width: 60, height: 60)

        XCTAssertEqual(seen(in: around, among: [crate, floor]), [crate, floor], "both show in it")
        XCTAssertEqual(selected(by: around), [crate], "only the crate is inside it")
    }

    func test_aRectangleOnTheWall_selectsNeitherTheWallNorWhatItHides() {
        _ = makeWallAndWhatIsBehind()

        XCTAssertEqual(selected(by: CGRect(x: 180, y: 130, width: 40, height: 40)), [], "the wall reaches out of it, and what is inside is hidden")
    }

    func test_withoutThePass_whatIsInsideIsSelected_seenOrNot() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        let byBoxes = MarqueeSelection.entities(inside: aroundTheWall, view: view(), selectionManager: selectionManager)

        XCTAssertEqual(Set(byBoxes), [wall, behind])
    }

    func test_whenThePassCannotTell_whatIsInsideIsSelected_seenOrNot() {
        let (wall, behind) = makeWallAndWhatIsBehind()

        let byBoxes = MarqueeSelection.entities(inside: aroundTheWall, view: view(), selectionManager: selectionManager, seen: { _, _, _ in nil })

        XCTAssertEqual(Set(byBoxes), [wall, behind])
    }

    func test_thePassIsNotAsked_whenNothingItCanTellAboutIsInside() {
        _ = makeWallAndWhatIsBehind()
        var asked = 0

        let chosen = MarqueeSelection.entities(
            inside: CGRect(x: 10, y: 10, width: 40, height: 40),
            view: view(),
            selectionManager: selectionManager,
            seen: { _, _, _ in
                asked += 1
                return []
            }
        )

        XCTAssertEqual(chosen, [])
        XCTAssertEqual(asked, 0, "a rectangle over nothing costs no pass")
    }

    func test_thePassIsHanded_onlyWhatMayShowInTheRectangle() {
        let (wall, behind) = makeWallAndWhatIsBehind()
        // A floor that shows in the rectangle and reaches far out of it.
        let floor = makeCube("Floor", at: simd_float3(0, -3.5, 0), side: 6)
        _ = makeCube("Beside", at: simd_float3(6, 0, -3))
        _ = makeCube("Behind the camera", at: simd_float3(0, 0, 9))
        var handed: [EntityID] = []

        _ = MarqueeSelection.entities(
            inside: aroundTheWall,
            view: view(),
            selectionManager: selectionManager,
            seen: { _, _, drawn in
                handed = drawn
                return Set(drawn)
            }
        )

        XCTAssertEqual(Set(handed), [wall, behind, floor], "what stands beside the rectangle or behind the camera is not drawn for it")
    }

    func test_whatCannotBeSelected_isHandedToThePassAllTheSame() {
        let (wall, behind) = makeWallAndWhatIsBehind()
        selectionManager.setLocked(wall, true)
        var handed: [EntityID] = []

        _ = MarqueeSelection.entities(
            inside: aroundTheWall,
            view: view(),
            selectionManager: selectionManager,
            seen: { _, _, drawn in
                handed = drawn
                return Set(drawn)
            }
        )

        XCTAssertEqual(Set(handed), [wall, behind], "a locked wall still hides what is behind it")
    }

    /// Leaving out of the pass what stands outside the rectangle changes
    /// nothing of what it tells: many cubes, some hiding others, and
    /// rectangles of several sizes.
    func test_drawingOnlyWhatMayShow_selectsTheSameAsDrawingEverything() {
        var generator = SeededGenerator(state: 11)
        // One cube of a unit, drawn by every entity at its own size: small
        // ones for the rectangles to hold, and a large one now and then that
        // reaches out of them and hides what is behind it.
        let unitCube = BasicPrimitives.createCube(extent: 1)
        var cubes: [EntityID] = []
        for index in 0 ..< 120 {
            let cube = createEntity()
            setEntityMeshDirect(entityId: cube, meshes: unitCube, assetName: "Cube \(index)")
            let side = index % 8 == 0 ? generator.next(in: 2.5 ... 5) : generator.next(in: 0.2 ... 1.2)
            scaleTo(entityId: cube, scale: simd_float3(repeating: side))
            translateTo(
                entityId: cube,
                position: simd_float3(generator.next(in: -7 ... 7), generator.next(in: -5 ... 5), generator.next(in: -12 ... 3))
            )
            cubes.append(cube)
        }
        let view = view()
        let rects = [
            CGRect(x: 0, y: 0, width: 400, height: 300),
            CGRect(x: 100, y: 60, width: 200, height: 180),
            CGRect(x: 20, y: 150, width: 160, height: 120),
            CGRect(x: 230, y: 20, width: 150, height: 130),
            CGRect(x: 180, y: 130, width: 40, height: 40),
        ]

        var chosen = 0
        var hidden = 0
        var leftOut = 0
        for rect in rects {
            let byBoxes = MarqueeSelection.entities(inside: rect, view: view, selectionManager: selectionManager)
            let shown = SelectionVisibilityPass.entitiesSeen(in: rect, view: view, scale: 2, drawn: cubes) ?? []
            let withEverythingDrawn = byBoxes.filter(shown.contains)

            let withWhatMayShowDrawn = MarqueeSelection.entities(
                inside: rect,
                view: view,
                selectionManager: selectionManager,
                seen: { rect, view, drawn in
                    leftOut += cubes.count - drawn.count
                    return SelectionVisibilityPass.entitiesSeen(in: rect, view: view, scale: 2, drawn: drawn)
                }
            )

            XCTAssertEqual(withWhatMayShowDrawn, withEverythingDrawn, "in \(rect)")
            chosen += withEverythingDrawn.count
            hidden += byBoxes.count - withEverythingDrawn.count
        }

        // Enough is selected, hidden and left out for the comparison to mean something.
        XCTAssertGreaterThan(chosen, 20)
        XCTAssertGreaterThan(hidden, 5)
        XCTAssertGreaterThan(leftOut, 100)
    }

    func test_theNearestOfThoseSeen_comesLast() {
        let far = makeCube("Far", at: simd_float3(-3, 0, -4))
        let near = makeCube("Near", at: simd_float3(2, 0, 2))
        let between = makeCube("Between", at: simd_float3(0, 0, -1))

        XCTAssertEqual(selected(by: CGRect(x: 0, y: 0, width: 400, height: 300)), [far, between, near])
    }

    func test_aLockedEntity_hidesWhatIsBehindIt_andIsNotSelected() {
        let (wall, _) = makeWallAndWhatIsBehind()
        selectionManager.setLocked(wall, true)

        XCTAssertEqual(selected(by: aroundTheWall), [])
    }

    func test_aHiddenEntity_hidesNothing() {
        let (wall, behind) = makeWallAndWhatIsBehind()
        selectionManager.setHidden(wall, true)

        XCTAssertEqual(selected(by: aroundTheWall), [behind])
    }

    func test_whatAClickPassesThrough_theRectangleSeesThrough() throws {
        let (wall, behind) = makeWallAndWhatIsBehind()
        let render = try XCTUnwrap(scene.get(component: RenderComponent.self, for: wall))
        for mesh in render.mesh.indices {
            for part in render.mesh[mesh].submeshes.indices {
                render.mesh[mesh].submeshes[part].material?.alphaMode = .blend
            }
        }
        XCTAssertEqual(selected(by: aroundTheWall), [wall], "glass is seen, and hides what is behind it")

        setIgnoreRayIntersectionWithTransparents(true)

        XCTAssertEqual(selected(by: aroundTheWall), [behind])
    }

    func test_anEntityWithoutMeshes_isSelectedByItsBoxAlone() {
        let (wall, _) = makeWallAndWhatIsBehind()
        let placeholder = createEntity()
        registerTransformComponent(entityId: placeholder)
        registerSceneGraphComponent(entityId: placeholder)
        registerComponent(entityId: placeholder, componentType: RenderComponent.self)
        scene.get(component: LocalTransformComponent.self, for: placeholder)?.boundingBox = (
            min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5)
        )
        translateTo(entityId: placeholder, position: simd_float3(0, 0, -3))

        XCTAssertFalse(MarqueeSelection.drawsMeshes(placeholder))
        XCTAssertEqual(Set(selected(by: aroundTheWall)), [wall, placeholder])
    }
}
