//
//  DockLayoutGeometryTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
import XCTest

final class DockLayoutGeometryTests: XCTestCase {
    private let divider = DockLayoutGeometry.dividerThickness
    private let viewportMinimum = PanelID.viewport.minimumSize

    func test_minimumLength_isTheWidestTabForASide_andTheTallestPlusTheStripForTheBottom() {
        XCTAssertEqual(DockLayoutGeometry.minimumLength(of: [.hierarchy, .console], in: .left), max(PanelID.hierarchy.minimumSize.width, PanelID.console.minimumSize.width))
        XCTAssertEqual(DockLayoutGeometry.minimumLength(of: [.assets, .console], in: .bottom), PanelID.assets.minimumSize.height + DockLayoutGeometry.tabStripHeight)
        XCTAssertEqual(DockLayoutGeometry.minimumLength(of: [], in: .left), 0)
    }

    func test_sideWidths_takeWhatTheyAskForWhenThereIsRoom() {
        let widths = DockLayoutGeometry.sideWidths(left: 250, leftMinimum: 200, right: 320, rightMinimum: 240, total: 1440)
        XCTAssertEqual(widths.left, 250)
        XCTAssertEqual(widths.right, 320)
    }

    func test_sideWidths_neverGoUnderTheirMinimums() {
        let widths = DockLayoutGeometry.sideWidths(left: 50, leftMinimum: 200, right: nil, rightMinimum: 240, total: 1440)
        XCTAssertEqual(widths.left, 200)
        XCTAssertEqual(widths.right, 0)
    }

    func test_sideWidths_shrinkTogetherToLeaveTheViewportItsMinimum() {
        let total = 800.0
        let widths = DockLayoutGeometry.sideWidths(left: 400, leftMinimum: 200, right: 400, rightMinimum: 240, total: total)
        let available = total - 2 * divider - viewportMinimum.width
        XCTAssertEqual(widths.left + widths.right, available, accuracy: 0.001)
        XCTAssertEqual(widths.left, widths.right, accuracy: 0.001)
    }

    func test_bottomHeight_isClampedBetweenItsMinimumAndTheViewportRoom() {
        XCTAssertEqual(DockLayoutGeometry.bottomHeight(250, minimum: 154, total: 800), 250)
        XCTAssertEqual(DockLayoutGeometry.bottomHeight(100, minimum: 154, total: 800), 154)
        XCTAssertEqual(DockLayoutGeometry.bottomHeight(700, minimum: 154, total: 800), 800 - divider - viewportMinimum.height)
        XCTAssertEqual(DockLayoutGeometry.bottomHeight(nil, minimum: 154, total: 800), 0)
    }

    func test_maximumLength_leavesTheViewportItsMinimum() {
        let size = CGSize(width: 1440, height: 800)
        XCTAssertEqual(DockLayoutGeometry.maximumLength(for: .left, in: size, otherSide: 320), 1440 - 320 - 2 * divider - viewportMinimum.width)
        XCTAssertEqual(DockLayoutGeometry.maximumLength(for: .left, in: size, otherSide: 0), 1440 - divider - viewportMinimum.width)
        XCTAssertEqual(DockLayoutGeometry.maximumLength(for: .bottom, in: size), 800 - divider - viewportMinimum.height)
    }

    func test_dropArea_edgesOfTheViewportPickAnArea_theMiddleNothing() {
        let size = CGSize(width: 400, height: 200)
        XCTAssertEqual(DockLayoutGeometry.dropArea(at: CGPoint(x: 20, y: 100), in: size), .left)
        XCTAssertEqual(DockLayoutGeometry.dropArea(at: CGPoint(x: 390, y: 100), in: size), .right)
        XCTAssertEqual(DockLayoutGeometry.dropArea(at: CGPoint(x: 200, y: 195), in: size), .bottom)
        XCTAssertNil(DockLayoutGeometry.dropArea(at: CGPoint(x: 200, y: 100), in: size))
        XCTAssertNil(DockLayoutGeometry.dropArea(at: CGPoint(x: 200, y: 10), in: size))
    }

    func test_viewportDropZoneRects_coverTheirEdges() {
        let size = CGSize(width: 400, height: 200)
        XCTAssertEqual(DockLayoutGeometry.viewportDropZoneRect(for: .left, in: size), CGRect(x: 0, y: 0, width: 100, height: 200))
        XCTAssertEqual(DockLayoutGeometry.viewportDropZoneRect(for: .right, in: size), CGRect(x: 300, y: 0, width: 100, height: 200))
        XCTAssertEqual(DockLayoutGeometry.viewportDropZoneRect(for: .bottom, in: size), CGRect(x: 0, y: 150, width: 400, height: 50))
    }
}
