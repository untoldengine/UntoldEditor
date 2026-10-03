//
//  ViewportOverlayHitTestTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import simd
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The overlays lie over the canvas and must not take its clicks: only the
/// navigation controls are in front of it, everything else lets the pointer
/// through to the scene.
@MainActor
final class ViewportOverlayHitTestTests: XCTestCase {
    /// Stands for the canvas under the overlays.
    private struct CanvasProbe: NSViewRepresentable {
        let canvas: NSView

        func makeNSView(context _: Context) -> NSView {
            canvas
        }

        func updateNSView(_: NSView, context _: Context) {}
    }

    private let size = CGSize(width: 800, height: 500)
    private var originalScene: UntoldEngine.Scene!
    private var originalActiveCamera: EntityID?
    private var originalGameMode = false
    private var window: NSWindow!
    private var canvas: NSView!
    private var store: ViewportOverlayStore!
    private var overlays: EditorViewportOverlaySettings!

    override func setUp() async throws {
        try await super.setUp()
        originalScene = scene
        originalActiveCamera = CameraSystem.shared.activeCamera
        originalGameMode = gameMode
        scene = UntoldEngine.Scene()
        gameMode = false
        let camera = findSceneCamera()
        cameraLookAt(entityId: camera, eye: simd_float3(3, 2, 5), target: .zero, up: simd_float3(0, 1, 0))
        CameraSystem.shared.activeCamera = camera

        store = ViewportOverlayStore()
        store.sample()
        overlays = EditorViewportOverlaySettings(defaults: nil)
        canvas = NSView(frame: NSRect(origin: .zero, size: size))
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        canvas = nil
        store = nil
        overlays = nil
        scene = originalScene
        CameraSystem.shared.activeCamera = originalActiveCamera
        gameMode = originalGameMode
        originalScene = nil
        try await super.tearDown()
    }

    /// Puts the canvas with the overlays over it in a window, laid out.
    private func show(showsEditorOverlays: Bool = true) {
        let content = CanvasProbe(canvas: canvas)
            .overlay {
                ViewportOverlaysView(
                    showsEditorOverlays: showsEditorOverlays,
                    showsStats: true,
                    showsHints: true,
                    mode: .object,
                    hasSelection: true,
                    onSelectView: { _ in },
                    overlays: overlays,
                    store: store
                )
            }
            .frame(width: size.width, height: size.height)

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.contentView?.layoutSubtreeIfNeeded()
        // The views of SwiftUI are made on the run loop's next turns.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// Whether a click at a point of the viewport, measured from its top
    /// left as the overlays are laid out, reaches the canvas.
    private func reachesTheCanvas(x: CGFloat, y: CGFloat) -> Bool {
        InputSystem.isEditorInputViewFrontmost(at: NSPoint(x: x, y: size.height - y), in: canvas)
    }

    private var gizmoCenter: CGPoint {
        let margin = ViewportOverlaysView.margin
        let radius = NavigationGizmoGeometry.diameter / 2
        return CGPoint(x: size.width - margin - radius, y: margin + radius)
    }

    func test_theCanvas_isLaidOutUnderTheOverlays() {
        show()

        XCTAssertNotNil(canvas.window)
        XCTAssertEqual(canvas.frame.width, size.width, accuracy: 1)
        XCTAssertEqual(canvas.frame.height, size.height, accuracy: 1)
        XCTAssertEqual(store.handles.count, 6)
    }

    func test_aClickInTheMiddle_reachesTheCanvas() {
        show()

        XCTAssertTrue(reachesTheCanvas(x: size.width / 2, y: size.height / 2))
    }

    func test_aClickOnTheBadgeOrTheStatistics_reachesTheCanvas() {
        show()

        XCTAssertTrue(reachesTheCanvas(x: 30, y: 22), "the badge")
        XCTAssertTrue(reachesTheCanvas(x: 30, y: 55), "the statistics")
    }

    func test_aClickOnTheHints_reachesTheCanvas() {
        show()

        XCTAssertTrue(reachesTheCanvas(x: size.width / 2, y: size.height - 23))
    }

    func test_theNavigationGizmo_takesThePointer() {
        show()

        XCTAssertFalse(reachesTheCanvas(x: gizmoCenter.x, y: gizmoCenter.y))
        XCTAssertFalse(reachesTheCanvas(x: gizmoCenter.x + 30, y: gizmoCenter.y))
    }

    func test_besideTheGizmosCircle_aClickReachesTheCanvas() {
        show()
        let radius = NavigationGizmoGeometry.diameter / 2

        // The corner of the square the circle sits in.
        XCTAssertTrue(reachesTheCanvas(x: gizmoCenter.x - radius + 3, y: gizmoCenter.y - radius + 3))
        XCTAssertTrue(reachesTheCanvas(x: gizmoCenter.x - radius - 20, y: gizmoCenter.y))
    }

    func test_theZoomAndPanButtons_takeThePointer() {
        show()
        let radius = NavigationGizmoGeometry.diameter / 2
        let zoomY = gizmoCenter.y + radius + 8 + NavigationDragButton.size / 2
        let panY = zoomY + NavigationDragButton.size + 8

        XCTAssertFalse(reachesTheCanvas(x: gizmoCenter.x, y: zoomY), "zoom")
        XCTAssertFalse(reachesTheCanvas(x: gizmoCenter.x, y: panY), "pan")
        XCTAssertTrue(reachesTheCanvas(x: gizmoCenter.x - 35, y: zoomY), "beside the buttons, under the gizmo")
    }

    func test_whileTheEditorsOverlaysAreOff_theWholeViewportIsTheCanvass() {
        show(showsEditorOverlays: false)

        XCTAssertTrue(reachesTheCanvas(x: gizmoCenter.x, y: gizmoCenter.y))
        XCTAssertTrue(reachesTheCanvas(x: size.width / 2, y: size.height / 2))
    }

    func test_aGizmoHiddenFromTheViewMenu_leavesItsPlaceToTheCanvas() {
        overlays.setShown(.navigationGizmo, false)
        show()

        XCTAssertTrue(reachesTheCanvas(x: gizmoCenter.x, y: gizmoCenter.y))
    }
}
