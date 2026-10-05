//
//  MarqueeGeometryTests.swift
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

/// What stands inside the rectangle dragged over the viewport, through a
/// camera and a projection of the engine.
///
/// The camera stands five units in front of the origin and sees a quarter
/// turn from top to bottom, so at a distance the viewport is twice that
/// distance high. The viewport is 400 points each way: its middle is at
/// (200, 200), and a unit of the world at the origin is 40 points. A box of
/// one unit at the origin reaches 22 points from the middle, where its near
/// face is.
final class MarqueeGeometryTests: XCTestCase {
    private var originalScene: Scene!
    private let size = CGSize(width: 400, height: 400)
    private let unitBox = (min: simd_float3(repeating: -0.5), max: simd_float3(repeating: 0.5))

    override func setUp() {
        super.setUp()
        originalScene = scene
        scene = Scene()
    }

    override func tearDown() {
        scene = originalScene
        originalScene = nil
        super.tearDown()
    }

    private func view(eye: simd_float3 = simd_float3(0, 0, 5), target: simd_float3 = .zero, size: CGSize? = nil) -> MarqueeGeometry.View {
        let size = size ?? self.size
        let camera = createEntity()
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        cameraLookAt(entityId: camera, eye: eye, target: target, up: simd_float3(0, 1, 0))
        return MarqueeGeometry.View(
            viewSpace: scene.get(component: CameraComponent.self, for: camera)?.viewSpace ?? matrix_identity_float4x4,
            perspectiveSpace: matrixPerspectiveRightHand(
                fovyRadians: .pi / 2,
                aspectRatio: Float(size.width / size.height),
                nearZ: 0.1,
                farZ: 100
            ),
            size: size
        )
    }

    private func contains(
        _ rect: CGRect,
        box: (min: simd_float3, max: simd_float3)? = nil,
        at position: simd_float3 = .zero,
        view: MarqueeGeometry.View? = nil
    ) -> Bool {
        let box = box ?? unitBox
        return MarqueeGeometry.contains(
            rect,
            boxMinimum: box.min,
            boxMaximum: box.max,
            modelSpace: matrix4x4Translation(position.x, position.y, position.z),
            view: view ?? self.view()
        )
    }

    // MARK: - The rectangle

    func test_theRectangle_isBetweenTheTwoPoints_whicheverWayTheDragWent() {
        let expected = CGRect(x: 10, y: 20, width: 30, height: 40)

        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 10, y: 20), to: CGPoint(x: 40, y: 60)), expected)
        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 40, y: 60), to: CGPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(MarqueeGeometry.rect(from: CGPoint(x: 10, y: 60), to: CGPoint(x: 40, y: 20)), expected)
    }

    func test_forAViewThatMeasuresFromItsTop_theRectangleIsTurnedOver() {
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)

        XCTAssertEqual(MarqueeGeometry.flipped(rect, inHeight: 400), CGRect(x: 10, y: 340, width: 30, height: 40))
    }

    func test_deviceCoordinates_runFromMinusOneToOne_withYUp() throws {
        let area = try XCTUnwrap(MarqueeGeometry.deviceRect(CGRect(x: 0, y: 300, width: 100, height: 100), in: size))

        XCTAssertEqual(area.low, simd_float2(-1, 0.5))
        XCTAssertEqual(area.high, simd_float2(-0.5, 1))
        XCTAssertNil(MarqueeGeometry.deviceRect(CGRect(x: 0, y: 0, width: 10, height: 10), in: .zero))
    }

    // MARK: - A box

    func test_aRectangleAroundTheBox_containsIt() {
        XCTAssertTrue(contains(CGRect(x: 150, y: 150, width: 100, height: 100)))
        XCTAssertTrue(contains(CGRect(x: 175, y: 175, width: 50, height: 50)), "three points to spare each way")
    }

    func test_aRectangleThatOnlyTouchesTheBox_doesNotContainIt() {
        XCTAssertFalse(contains(CGRect(x: 190, y: 150, width: 100, height: 100)), "the left of the box is out")
        XCTAssertFalse(contains(CGRect(x: 150, y: 150, width: 60, height: 100)), "its right is out")
        XCTAssertFalse(contains(CGRect(x: 195, y: 195, width: 10, height: 10)), "a rectangle on its face")
        XCTAssertFalse(contains(CGRect(x: 180, y: 180, width: 40, height: 40)), "around its far face, short of its near one")
    }

    func test_aRectangleAwayFromTheBox_doesNot() {
        XCTAssertFalse(contains(CGRect(x: 10, y: 10, width: 50, height: 50)))
    }

    func test_aDragStraightAcross_containsNoBox() {
        XCTAssertFalse(contains(MarqueeGeometry.rect(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200))))
    }

    func test_theBoxIsTakenWhereItsEntityStands() {
        // Two units to the right at five away: 80 points right of the middle.
        let position = simd_float3(2, 0, 0)

        XCTAssertTrue(contains(CGRect(x: 250, y: 170, width: 70, height: 60), at: position))
        XCTAssertFalse(contains(CGRect(x: 150, y: 150, width: 100, height: 100), at: position))
    }

    func test_upInTheWorld_isUpInTheRectanglesMeasure() {
        let position = simd_float3(0, 2, 0)

        XCTAssertTrue(contains(CGRect(x: 170, y: 250, width: 60, height: 70), at: position))
        XCTAssertFalse(contains(CGRect(x: 170, y: 80, width: 60, height: 70), at: position))
    }

    func test_aTurnedBox_isInsideWhereItsCornersReach() {
        // A box two wide and thin, turned a quarter about Z: it stands tall.
        let tall = simd_float4x4(simd_quatf(angle: .pi / 2, axis: simd_float3(0, 0, 1)))
        let box = (min: simd_float3(-1, -0.1, -0.1), max: simd_float3(1, 0.1, 0.1))
        let upright = CGRect(x: 190, y: 150, width: 20, height: 100)
        let lying = CGRect(x: 150, y: 190, width: 100, height: 20)

        XCTAssertTrue(MarqueeGeometry.contains(upright, boxMinimum: box.min, boxMaximum: box.max, modelSpace: tall, view: view()))
        XCTAssertFalse(MarqueeGeometry.contains(lying, boxMinimum: box.min, boxMaximum: box.max, modelSpace: tall, view: view()))
        XCTAssertTrue(MarqueeGeometry.contains(lying, boxMinimum: box.min, boxMaximum: box.max, modelSpace: matrix_identity_float4x4, view: view()))
        XCTAssertFalse(MarqueeGeometry.contains(upright, boxMinimum: box.min, boxMaximum: box.max, modelSpace: matrix_identity_float4x4, view: view()))
    }

    func test_inAWideViewport_theMiddleIsWhereTheBoxIs() {
        let wide = view(size: CGSize(width: 800, height: 400))

        XCTAssertTrue(contains(CGRect(x: 370, y: 170, width: 60, height: 60), view: wide))
        XCTAssertFalse(contains(CGRect(x: 170, y: 170, width: 60, height: 60), view: wide))
    }

    func test_aViewportWithNoSize_containsNothing() {
        XCTAssertFalse(contains(CGRect(x: 0, y: 0, width: 10, height: 10), view: view(size: CGSize(width: 0, height: 400))))
    }

    // MARK: - What reaches out of the rectangle

    func test_aFloorUnderTheRectangle_isNotInside() {
        // A floor twenty units each way, a unit under the origin: it shows
        // in every rectangle drawn over the lower half of the viewport.
        let floor = (min: simd_float3(-10, -1.1, -10), max: simd_float3(10, -1, 10))

        XCTAssertFalse(contains(CGRect(x: 150, y: 100, width: 100, height: 100), box: floor))
        XCTAssertFalse(contains(CGRect(x: 0, y: 0, width: 400, height: 400), box: floor), "not even the whole viewport holds it")
    }

    func test_aBoxBehindTheCamera_isNotInside() {
        XCTAssertFalse(contains(CGRect(x: 0, y: 0, width: 400, height: 400), at: simd_float3(0, 0, 10)))
    }

    func test_aBoxThatReachesBehindTheCamera_isNotInside() {
        // A long beam along the view, the camera inside it.
        let beam = (min: simd_float3(-0.5, -0.5, -20), max: simd_float3(0.5, 0.5, 20))

        XCTAssertFalse(contains(CGRect(x: 0, y: 0, width: 400, height: 400), box: beam))
    }

    func test_aBoxTheCameraIsInsideOf_isNotInside() {
        // A room twenty units each way, the camera in it: a rectangle drawn
        // in the room does not select the room.
        let room = (min: simd_float3(repeating: -10), max: simd_float3(repeating: 10))

        XCTAssertFalse(contains(CGRect(x: 190, y: 190, width: 20, height: 20), box: room))
        XCTAssertFalse(contains(CGRect(x: 0, y: 0, width: 400, height: 400), box: room))
    }

    // MARK: - Where a box stands to the rectangle

    private func place(
        _ rect: CGRect,
        box: (min: simd_float3, max: simd_float3)? = nil,
        at position: simd_float3 = .zero,
        view: MarqueeGeometry.View? = nil
    ) -> MarqueeGeometry.Place {
        let box = box ?? unitBox
        return MarqueeGeometry.place(
            ofBoxMinimum: box.min,
            boxMaximum: box.max,
            modelSpace: matrix4x4Translation(position.x, position.y, position.z),
            in: rect,
            view: view ?? self.view()
        )
    }

    func test_aBoxAllInTheRectangle_isInside_andOneTheRectangleCuts_isAcross() {
        XCTAssertEqual(place(CGRect(x: 150, y: 150, width: 100, height: 100)), .inside)
        XCTAssertEqual(place(CGRect(x: 190, y: 150, width: 100, height: 100)), .across, "the left of the box is out")
        XCTAssertEqual(place(CGRect(x: 195, y: 195, width: 10, height: 10)), .across, "a rectangle on its face")
        XCTAssertEqual(place(CGRect(x: 180, y: 180, width: 40, height: 40)), .across, "around its far face, short of its near one")
    }

    func test_aBoxBeyondOneSideOfTheRectangle_isOutside() {
        // The box shows from 178 to 222 points each way.
        XCTAssertEqual(place(CGRect(x: 230, y: 150, width: 100, height: 100)), .outside, "the rectangle is right of it")
        XCTAssertEqual(place(CGRect(x: 70, y: 150, width: 100, height: 100)), .outside, "left of it")
        XCTAssertEqual(place(CGRect(x: 150, y: 230, width: 100, height: 100)), .outside, "above it")
        XCTAssertEqual(place(CGRect(x: 150, y: 70, width: 100, height: 100)), .outside, "below it")
        XCTAssertEqual(place(CGRect(x: 10, y: 10, width: 50, height: 50)), .outside)
    }

    func test_aBoxThatTouchesTheBorder_isNotOutside() {
        // The near face ends 22.2 points right of the middle.
        XCTAssertEqual(place(CGRect(x: 222, y: 150, width: 100, height: 100)), .across)
        XCTAssertEqual(place(CGRect(x: 223, y: 150, width: 100, height: 100)), .outside)
    }

    func test_aBoxBehindTheCamera_isOutside_andOneThatReachesBehindIt_isNot() {
        let everything = CGRect(x: 0, y: 0, width: 400, height: 400)
        let beam = (min: simd_float3(-0.5, -0.5, -20), max: simd_float3(0.5, 0.5, 20))
        // A wall five units behind the camera, far wider than the view: it is
        // beyond no side of the rectangle with all of it.
        let wallBehind = (min: simd_float3(-10, -10, 9.9), max: simd_float3(10, 10, 10.1))

        XCTAssertEqual(place(everything, at: simd_float3(0, 0, 10)), .outside)
        XCTAssertEqual(place(everything, box: wallBehind), .outside)
        XCTAssertEqual(place(CGRect(x: 190, y: 190, width: 20, height: 20), box: wallBehind), .outside)
        XCTAssertEqual(place(everything, box: beam), .across, "the camera is in the beam")
        XCTAssertEqual(place(CGRect(x: 10, y: 10, width: 50, height: 50), box: beam), .across, "and its walls are all around the view")
    }

    func test_theRoomTheCameraIsIn_isAcrossEveryRectangle() {
        let room = (min: simd_float3(repeating: -10), max: simd_float3(repeating: 10))

        XCTAssertEqual(place(CGRect(x: 190, y: 190, width: 20, height: 20), box: room), .across)
        XCTAssertEqual(place(CGRect(x: 0, y: 0, width: 10, height: 10), box: room), .across)
        XCTAssertEqual(place(CGRect(x: 0, y: 0, width: 400, height: 400), box: room), .across)
    }

    func test_aFloor_isAcrossARectangleOverIt_andOutsideOneAboveTheHorizon() {
        // A floor a unit under the camera's height, that reaches behind the
        // camera: all that shows of it is below the middle of the view.
        let floor = (min: simd_float3(-10, -1.1, -10), max: simd_float3(10, -1, 10))

        XCTAssertEqual(place(CGRect(x: 150, y: 100, width: 100, height: 100), box: floor), .across)
        XCTAssertEqual(place(CGRect(x: 150, y: 220, width: 100, height: 100), box: floor), .outside)
    }

    func test_aViewportWithNoSize_hasEveryBoxOutside() {
        XCTAssertEqual(place(CGRect(x: 0, y: 0, width: 10, height: 10), view: view(size: CGSize(width: 0, height: 400))), .outside)
    }

    func test_aBoxThatIsNowhere_isAcross_asThereIsNoTelling() {
        let nowhere = MarqueeGeometry.place(
            ofBoxMinimum: unitBox.min,
            boxMaximum: unitBox.max,
            modelSpace: matrix4x4Translation(.nan, 0, 0),
            in: CGRect(x: 150, y: 150, width: 100, height: 100),
            view: view()
        )

        XCTAssertEqual(nowhere, .across)
    }

    /// The answer `outside` leaves an entity out of what is drawn to tell
    /// what is seen, so it must never be given for a box that shows in the
    /// rectangle: turned boxes of every size, around the camera and behind it.
    func test_noBoxToldOutside_hasAPointThatShowsInTheRectangle() {
        var generator = SeededGenerator(state: 7)
        let view = view()
        var outside = 0
        var across = 0
        var inside = 0

        for _ in 0 ..< 3000 {
            let half = simd_float3(generator.next(in: 0.05 ... 3), generator.next(in: 0.05 ... 3), generator.next(in: 0.05 ... 3))
            let turn = simd_quatf(
                angle: generator.next(in: 0 ... 2 * .pi),
                axis: simd_normalize(simd_float3(generator.next(in: -1 ... 1), generator.next(in: -1 ... 1), generator.next(in: 0.1 ... 1)))
            )
            let position = simd_float3(generator.next(in: -8 ... 8), generator.next(in: -8 ... 8), generator.next(in: -12 ... 9))
            let modelSpace = simd_mul(matrix4x4Translation(position.x, position.y, position.z), simd_float4x4(turn))
            let origin = CGPoint(x: CGFloat(generator.next(in: 0 ... 360)), y: CGFloat(generator.next(in: 0 ... 360)))
            let rect = CGRect(
                origin: origin,
                size: CGSize(width: CGFloat(generator.next(in: 1 ... 200)), height: CGFloat(generator.next(in: 1 ... 200)))
            )

            let place = MarqueeGeometry.place(ofBoxMinimum: -half, boxMaximum: half, modelSpace: modelSpace, in: rect, view: view)

            // Points all through the box, its corners among them.
            var shows = 0
            var points = 0
            let steps: [Float] = [-1, -0.5, 0, 0.5, 1]
            for x in steps {
                for y in steps {
                    for z in steps {
                        let world = simd_mul(modelSpace, simd_float4(half * simd_float3(x, y, z), 1))
                        points += 1
                        shows += MarqueeGeometry.contains(rect, point: simd_float3(world.x, world.y, world.z), view: view) ? 1 : 0
                    }
                }
            }

            switch place {
            case .outside:
                outside += 1
                XCTAssertEqual(shows, 0, "a box told outside shows in \(rect)")
            case .inside:
                inside += 1
                XCTAssertEqual(shows, points, "a box told inside reaches out of \(rect)")
            case .across:
                across += 1
            }
        }

        // The three answers all came up, so each of them was put to the test.
        XCTAssertGreaterThan(outside, 300)
        XCTAssertGreaterThan(across, 300)
        XCTAssertGreaterThan(inside, 3)
    }

    // MARK: - A point

    func test_aPoint_isInsideTheRectangleItIsIn() {
        let view = view()

        XCTAssertTrue(MarqueeGeometry.contains(CGRect(x: 190, y: 190, width: 20, height: 20), point: .zero, view: view))
        XCTAssertFalse(MarqueeGeometry.contains(CGRect(x: 210, y: 190, width: 20, height: 20), point: .zero, view: view))
        XCTAssertTrue(MarqueeGeometry.contains(CGRect(x: 200, y: 190, width: 20, height: 20), point: .zero, view: view), "the border counts")
    }

    func test_aPointBehindTheCamera_isNotInside() {
        XCTAssertFalse(MarqueeGeometry.contains(
            CGRect(x: 0, y: 0, width: 400, height: 400),
            point: simd_float3(0, 0, 10),
            view: view()
        ))
    }

    func test_inDeviceCoordinates_aPlaceIsInsideUpToTheBorder_andOnlyInFrontOfTheCamera() {
        let area = MarqueeGeometry.DeviceRect(low: simd_float2(-0.5, -0.5), high: simd_float2(0.5, 0.5))

        XCTAssertTrue(area.contains(simd_float4(0.2, -0.2, 0, 1)))
        XCTAssertTrue(area.contains(simd_float4(1, 1, 0, 2)), "on the corner, once divided by its depth")
        XCTAssertFalse(area.contains(simd_float4(0.6, 0, 0, 1)), "beside it")
        XCTAssertFalse(area.contains(simd_float4(0.2, 0.2, 0, -1)), "behind the camera")
        XCTAssertFalse(area.contains(simd_float4(.nan, 0, 0, 1)))
    }
}
