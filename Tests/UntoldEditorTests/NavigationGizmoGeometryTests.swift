//
//  NavigationGizmoGeometryTests.swift
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

/// Where the navigation gizmo puts the world's axes for a camera of the
/// engine, and which end a click lands on.
final class NavigationGizmoGeometryTests: XCTestCase {
    private var originalScene: Scene!

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

    /// The view matrix of a camera of the engine that looks at `target` from `eye`.
    private func viewSpace(eye: simd_float3, target: simd_float3 = .zero, up: simd_float3 = simd_float3(0, 1, 0)) -> simd_float4x4 {
        let camera = createEntity()
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        cameraLookAt(entityId: camera, eye: eye, target: target, up: up)
        return scene.get(component: CameraComponent.self, for: camera)?.viewSpace ?? matrix_identity_float4x4
    }

    private func handle(_ axis: NavigationAxis, positive: Bool, in handles: [NavigationGizmoHandle]) -> NavigationGizmoHandle? {
        handles.first { $0.axis == axis && $0.isPositive == positive }
    }

    private func assertHandle(
        _ handle: NavigationGizmoHandle?,
        offset: simd_float2,
        depth: Float,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let handle else {
            XCTFail("the end is missing", file: file, line: line)
            return
        }
        XCTAssertEqual(handle.offset.x, offset.x, accuracy: 0.001, "x", file: file, line: line)
        XCTAssertEqual(handle.offset.y, offset.y, accuracy: 0.001, "y", file: file, line: line)
        XCTAssertEqual(handle.depth, depth, accuracy: 0.001, "depth", file: file, line: line)
    }

    func test_fromTheFront_xRunsRight_yRunsUp_andZComesToTheViewer() {
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(0, 0, 5)))

        XCTAssertEqual(handles.count, 6)
        assertHandle(handle(.x, positive: true, in: handles), offset: simd_float2(1, 0), depth: 0)
        assertHandle(handle(.x, positive: false, in: handles), offset: simd_float2(-1, 0), depth: 0)
        assertHandle(handle(.y, positive: true, in: handles), offset: simd_float2(0, 1), depth: 0)
        assertHandle(handle(.y, positive: false, in: handles), offset: simd_float2(0, -1), depth: 0)
        assertHandle(handle(.z, positive: true, in: handles), offset: simd_float2(0, 0), depth: 1)
        assertHandle(handle(.z, positive: false, in: handles), offset: simd_float2(0, 0), depth: -1)
    }

    func test_fromAbove_yComesToTheViewer_andZRunsDownTheScreen() throws {
        let top = try XCTUnwrap(ViewportProjection.top.view)
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: top.direction * 5, up: top.up))

        assertHandle(handle(.y, positive: true, in: handles), offset: simd_float2(0, 0), depth: 1)
        assertHandle(handle(.x, positive: true, in: handles), offset: simd_float2(1, 0), depth: 0)
        assertHandle(handle(.z, positive: true, in: handles), offset: simd_float2(0, -1), depth: 0)
    }

    func test_fromTheRight_xComesToTheViewer_andZRunsLeft() {
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(5, 0, 0)))

        assertHandle(handle(.x, positive: true, in: handles), offset: simd_float2(0, 0), depth: 1)
        assertHandle(handle(.z, positive: true, in: handles), offset: simd_float2(-1, 0), depth: 0)
        assertHandle(handle(.y, positive: true, in: handles), offset: simd_float2(0, 1), depth: 0)
    }

    func test_theEnds_comeFarthestFirst_soTheNearestIsDrawnLast() {
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(3, 2, 5)))

        XCTAssertEqual(handles.map(\.depth), handles.map(\.depth).sorted())
        // From the front, right and above, the three positive ends are the near ones.
        XCTAssertEqual(Set(handles.suffix(3).map(\.isPositive)), [true])
    }

    func test_theOrder_isTheSameForTheSameCamera() {
        let matrix = viewSpace(eye: simd_float3(0, 0, 5))
        let first = NavigationGizmoGeometry.handles(viewSpace: matrix)

        for _ in 0 ..< 5 {
            XCTAssertEqual(NavigationGizmoGeometry.handles(viewSpace: matrix), first)
        }
    }

    func test_anEnd_sitsAnArmFromTheCentre() throws {
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(0, 0, 5)))
        let diameter = NavigationGizmoGeometry.diameter
        let arm = NavigationGizmoGeometry.armLength

        let right = try NavigationGizmoGeometry.center(of: XCTUnwrap(handle(.x, positive: true, in: handles)))
        XCTAssertEqual(right.x, diameter / 2 + arm, accuracy: 0.001)
        XCTAssertEqual(right.y, diameter / 2, accuracy: 0.001)

        // Up the screen is a smaller y.
        let up = try NavigationGizmoGeometry.center(of: XCTUnwrap(handle(.y, positive: true, in: handles)))
        XCTAssertEqual(up.x, diameter / 2, accuracy: 0.001)
        XCTAssertEqual(up.y, diameter / 2 - arm, accuracy: 0.001)
    }

    func test_theBallsAndTheRings_stayInsideTheCircle() {
        let reach = NavigationGizmoGeometry.armLength + NavigationGizmoGeometry.ballDiameter / 2
        XCTAssertLessThanOrEqual(reach, NavigationGizmoGeometry.diameter / 2)
    }

    func test_aClick_landsOnTheEndUnderIt() {
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(0, 0, 5)))
        let center = NavigationGizmoGeometry.diameter / 2
        let arm = NavigationGizmoGeometry.armLength

        let right = NavigationGizmoGeometry.handle(at: CGPoint(x: center + arm, y: center), in: handles)
        XCTAssertEqual(right?.axis, .x)
        XCTAssertEqual(right?.isPositive, true)

        let below = NavigationGizmoGeometry.handle(at: CGPoint(x: center, y: center + arm), in: handles)
        XCTAssertEqual(below?.axis, .y)
        XCTAssertEqual(below?.isPositive, false)

        XCTAssertNil(NavigationGizmoGeometry.handle(at: CGPoint(x: center + arm / 2, y: center + arm / 2), in: handles))
    }

    func test_aClickOnTwoEnds_takesTheOneNearerTheViewer() {
        // From the front both ends of Z are at the centre, the positive one in front.
        let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: simd_float3(0, 0, 5)))
        let center = NavigationGizmoGeometry.diameter / 2

        let hit = NavigationGizmoGeometry.handle(at: CGPoint(x: center, y: center), in: handles)

        XCTAssertEqual(hit?.axis, .z)
        XCTAssertEqual(hit?.isPositive, true)
    }

    func test_anEnd_goesToTheViewFromItsSide() {
        let expected: [(NavigationAxis, Bool, ViewportProjection)] = [
            (.x, true, .right), (.x, false, .left),
            (.y, true, .top), (.y, false, .bottom),
            (.z, true, .front), (.z, false, .back),
        ]
        for (axis, isPositive, projection) in expected {
            let handle = NavigationGizmoHandle(axis: axis, isPositive: isPositive, offset: .zero, depth: 0)
            XCTAssertEqual(handle.projection, projection)
            // The camera stands on that side of the pivot.
            let side = axis.direction * (isPositive ? 1 : -1)
            XCTAssertEqual(projection.view?.direction, side)
        }
    }

    func test_afterAClick_theEndFacesTheViewer() {
        for projection in ViewportProjection.presets {
            guard let view = projection.view else { continue }
            let handles = NavigationGizmoGeometry.handles(viewSpace: viewSpace(eye: view.direction * 5, up: view.up))

            let facing = handles.last
            XCTAssertEqual(facing?.projection, projection)
            XCTAssertEqual(facing?.depth ?? 0, 1, accuracy: 0.001)
        }
    }
}
