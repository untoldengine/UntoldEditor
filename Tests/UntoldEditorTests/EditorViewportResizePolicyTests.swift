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

    func testApplyIsIdempotent() {
        let view = makeView()

        EditorViewportResizePolicy.apply(to: view)
        EditorViewportResizePolicy.apply(to: view)

        XCTAssertEqual(view.layer?.contentsGravity, .center)
        XCTAssertNotNil(view.layer?.backgroundColor)
    }
}
