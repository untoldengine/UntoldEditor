//
//  EditorViewportResizePolicyTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import MetalKit
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

@MainActor
final class EditorViewportResizePolicyTests: XCTestCase {
    private func makeView() -> MTKView {
        MTKView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
    }

    func testApplyAnchorsLastFrameToCentreInsteadOfStretching() {
        let view = makeView()
        XCTAssertEqual(view.layer?.contentsGravity, .resize, "MTKView stretches the last frame by default")

        EditorViewportResizePolicy.apply(to: view)

        XCTAssertEqual(view.layer?.contentsGravity, .center)
    }

    func testApplyPaintsExposedEdgesWithEngineBackgroundColour() throws {
        let view = makeView()

        EditorViewportResizePolicy.apply(to: view)

        let color = try XCTUnwrap(view.layer?.backgroundColor)
        XCTAssertEqual(color.colorSpace?.name, CGColorSpace.linearSRGB)
        let components = try XCTUnwrap(color.components)
        XCTAssertEqual(components.count, 4)
        let expected = EditorViewportResizePolicy.exposedBackgroundColor
        XCTAssertEqual(components[0], CGFloat(expected.x), accuracy: 1e-5)
        XCTAssertEqual(components[1], CGFloat(expected.y), accuracy: 1e-5)
        XCTAssertEqual(components[2], CGFloat(expected.z), accuracy: 1e-5)
        XCTAssertEqual(components[3], 1.0, accuracy: 1e-5)
    }

    func testExposedBackgroundMatchesEngineMainPassClearColour() {
        // The engine clears its main pass to (40, 40, 45) / 255; keep the mirror in sync.
        let c = EditorViewportResizePolicy.exposedBackgroundColor
        XCTAssertEqual(c.x, 40.0 / 255.0, accuracy: 1e-6)
        XCTAssertEqual(c.y, 40.0 / 255.0, accuracy: 1e-6)
        XCTAssertEqual(c.z, 45.0 / 255.0, accuracy: 1e-6)
        XCTAssertEqual(c.w, 1.0)
    }

    func testApplyClipsTheFrozenFrameToTheView() {
        let view = makeView()
        XCTAssertFalse(view.clipsToBounds, "AppKit no longer clips by default; the policy must opt in")

        EditorViewportResizePolicy.apply(to: view)

        XCTAssertTrue(view.clipsToBounds)
        XCTAssertEqual(view.layer?.masksToBounds, true)
    }

    /// A window on a 1x external display beside a 2x main screen: MTKView sizes
    /// the drawable at 1x while the layer still carries the creation-time 2x.
    func testSyncContentsScaleFollowsA1xDrawableUnderAStale2xLayer() {
        let view = makeView()
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 320, height: 200)
        view.layer?.contentsScale = 2.0

        let scale = EditorViewportResizePolicy.syncContentsScale(of: view)

        XCTAssertEqual(scale, 1.0)
        XCTAssertEqual(view.layer?.contentsScale, 1.0)
    }

    func testSyncContentsScaleKeepsARetinaDrawableAt2x() {
        let view = makeView()
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 640, height: 400)
        view.layer?.contentsScale = 1.0

        let scale = EditorViewportResizePolicy.syncContentsScale(of: view)

        XCTAssertEqual(scale, 2.0)
        XCTAssertEqual(view.layer?.contentsScale, 2.0)
    }

    func testSyncContentsScaleLeavesAnUnsizedViewAlone() {
        let view = MTKView(frame: .zero)
        view.layer?.contentsScale = 2.0

        XCTAssertNil(EditorViewportResizePolicy.syncContentsScale(of: view))
        XCTAssertEqual(view.layer?.contentsScale, 2.0)
    }

    func testApplySyncsTheScaleToo() {
        let view = makeView()
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 320, height: 200)
        view.layer?.contentsScale = 2.0

        EditorViewportResizePolicy.apply(to: view)

        XCTAssertEqual(view.layer?.contentsScale, 1.0)
    }

    // MARK: - Resize hold

    func testOverscanFieldOfViewKeepsTheVisibleCropUnchanged() {
        let widened = EditorViewportResizePolicy.overscanFieldOfView(fov: 45, visibleHeight: 500, overscanHeight: 1000)

        // The central 500 of 1000 points must span the same half-height as the 45° render.
        XCTAssertEqual(tan(widened * .pi / 360) * 0.5, tan(Float(45) * .pi / 360), accuracy: 1e-5)
        XCTAssertEqual(widened, 79.28, accuracy: 0.01)
    }

    func testOverscanFieldOfViewIsUnchangedWhenThereIsNothingToGrow() {
        XCTAssertEqual(EditorViewportResizePolicy.overscanFieldOfView(fov: 45, visibleHeight: 500, overscanHeight: 500), 45)
        XCTAssertEqual(EditorViewportResizePolicy.overscanFieldOfView(fov: 45, visibleHeight: 500, overscanHeight: 400), 45)
        XCTAssertEqual(EditorViewportResizePolicy.overscanFieldOfView(fov: 45, visibleHeight: 0, overscanHeight: 500), 45)
    }

    func testOverscanSizeGrowsTheVisibleAreaToTheScreen() {
        let visible = CGSize(width: 800, height: 500)
        XCTAssertEqual(
            EditorViewportResizePolicy.overscanSize(visible: visible, screen: CGSize(width: 1728, height: 1117)),
            CGSize(width: 1728, height: 1117)
        )
        XCTAssertEqual(EditorViewportResizePolicy.overscanSize(visible: visible, screen: nil), visible)
        XCTAssertEqual(
            EditorViewportResizePolicy.overscanSize(visible: CGSize(width: 2000, height: 300), screen: CGSize(width: 1728, height: 1117)),
            CGSize(width: 2000, height: 1117)
        )
    }

    func testResizeHoldRendersAtScreenSizeThenRestores() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 400),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let metal = makeView()
        let host = EditorViewportHostView(metalView: metal)
        window.contentView = host
        let screen = try XCTUnwrap(window.screen?.frame.size)
        let original = fov
        defer { fov = original }

        EditorViewportResizePolicy.beginResizeHold(of: metal)

        XCTAssertTrue(metal.isPaused)
        let expected = EditorViewportResizePolicy.overscanSize(visible: host.bounds.size, screen: screen)
        XCTAssertEqual(host.heldMetalViewSize, expected)
        XCTAssertEqual(metal.frame.size, expected)
        XCTAssertGreaterThan(fov, original)

        EditorViewportResizePolicy.endResizeHold(of: metal)

        XCTAssertFalse(metal.isPaused)
        XCTAssertNil(host.heldMetalViewSize)
        XCTAssertEqual(metal.frame, host.bounds)
        XCTAssertEqual(fov, original)
        XCTAssertEqual((metal.layer as? CAMetalLayer)?.presentsWithTransaction, false)
    }

    func testResizeHoldWithoutAHostOnlyPauses() {
        let metal = makeView()
        let original = fov
        defer { fov = original }

        EditorViewportResizePolicy.beginResizeHold(of: metal)
        XCTAssertTrue(metal.isPaused)
        XCTAssertEqual(fov, original)

        EditorViewportResizePolicy.endResizeHold(of: metal)
        XCTAssertFalse(metal.isPaused)
    }

    func testApplyIsIdempotent() {
        let view = makeView()

        EditorViewportResizePolicy.apply(to: view)
        EditorViewportResizePolicy.apply(to: view)

        XCTAssertEqual(view.layer?.contentsGravity, .center)
        XCTAssertNotNil(view.layer?.backgroundColor)
    }
}
