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

    func testApplyIsIdempotent() {
        let view = makeView()

        EditorViewportResizePolicy.apply(to: view)
        EditorViewportResizePolicy.apply(to: view)

        XCTAssertEqual(view.layer?.contentsGravity, .center)
        XCTAssertNotNil(view.layer?.backgroundColor)
    }
}
