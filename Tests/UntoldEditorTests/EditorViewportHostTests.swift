//
//  EditorViewportHostTests.swift
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
final class EditorViewportHostTests: XCTestCase {
    private func makeHost(size: CGSize) -> (EditorViewportHostView, MTKView) {
        let metal = MTKView(frame: .zero)
        let host = EditorViewportHostView(metalView: metal)
        host.frame = CGRect(origin: .zero, size: size)
        return (host, metal)
    }

    func testMetalViewFillsTheHostAndTheHostClips() {
        let (host, metal) = makeHost(size: CGSize(width: 800, height: 500))

        XCTAssertTrue(metal.superview === host)
        XCTAssertTrue(host.clipsToBounds)
        XCTAssertEqual(metal.frame, host.bounds)
    }

    func testMetalViewFollowsHostResizes() {
        let (host, metal) = makeHost(size: CGSize(width: 800, height: 500))

        host.frame = CGRect(x: 0, y: 0, width: 1200, height: 700)

        XCTAssertEqual(metal.frame, CGRect(x: 0, y: 0, width: 1200, height: 700))
    }

    func testHeldSizeCentresTheMetalViewOnWholePoints() {
        let (host, metal) = makeHost(size: CGSize(width: 801, height: 501))

        host.heldMetalViewSize = CGSize(width: 1000, height: 700)

        XCTAssertEqual(metal.frame, CGRect(x: -100, y: -100, width: 1000, height: 700))
    }

    func testHeldMetalViewStaysCentredWhileTheHostResizes() {
        let (host, metal) = makeHost(size: CGSize(width: 800, height: 500))
        host.heldMetalViewSize = CGSize(width: 1000, height: 700)

        host.frame = CGRect(x: 0, y: 0, width: 900, height: 600)

        XCTAssertEqual(metal.frame, CGRect(x: -50, y: -50, width: 1000, height: 700))
    }

    func testReleasingTheHeldSizeFillsTheHostAgain() {
        let (host, metal) = makeHost(size: CGSize(width: 800, height: 500))
        host.heldMetalViewSize = CGSize(width: 1000, height: 700)

        host.heldMetalViewSize = nil

        XCTAssertEqual(metal.frame, host.bounds)
    }

    func testMetalViewFrameMath() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
        XCTAssertEqual(EditorViewportHostView.metalViewFrame(in: bounds, held: nil), bounds)
        XCTAssertEqual(
            EditorViewportHostView.metalViewFrame(in: bounds, held: CGSize(width: 1000, height: 1000)),
            CGRect(x: -180, y: -300, width: 1000, height: 1000)
        )
    }
}
