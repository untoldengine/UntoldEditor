//
//  FloatingPanelFramesTests.swift
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

final class FloatingPanelFramesTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    func test_defaultSize_isTallForSidePanels_wideForBottomOnes_andNeverUnderTheMinimum() {
        XCTAssertEqual(FloatingPanelFrames.defaultSize(for: .inspector), CGSize(width: 320, height: 560))
        XCTAssertEqual(FloatingPanelFrames.defaultSize(for: .hierarchy), CGSize(width: 320, height: 560))
        XCTAssertEqual(FloatingPanelFrames.defaultSize(for: .console), CGSize(width: 640, height: 360))
        for panel in PanelID.available where panel.isDockable {
            let size = FloatingPanelFrames.defaultSize(for: panel)
            XCTAssertGreaterThanOrEqual(size.width, panel.minimumSize.width, "\(panel)")
            XCTAssertGreaterThanOrEqual(size.height, panel.minimumSize.height, "\(panel)")
        }
    }

    func test_defaultFrame_cascadesFromTheEditorWindowsTopRightCorner() {
        let parent = CGRect(x: 100, y: 100, width: 1600, height: 1000)

        let first = FloatingPanelFrames.defaultFrame(for: .console, beside: parent, index: 0)
        XCTAssertEqual(first, CGRect(x: 1700 - 640 - 40, y: 1100 - 360 - 80, width: 640, height: 360))

        let second = FloatingPanelFrames.defaultFrame(for: .console, beside: parent, index: 1)
        XCTAssertEqual(second.origin, CGPoint(x: first.minX - 24, y: first.minY - 24))
        XCTAssertEqual(second.size, first.size)
    }

    func test_isReachable_needsEnoughOfTheTitleBarOnAScreen() {
        XCTAssertTrue(FloatingPanelFrames.isReachable(CGRect(x: 100, y: 100, width: 400, height: 300), on: [screen]))
        XCTAssertTrue(
            FloatingPanelFrames.isReachable(CGRect(x: 100, y: -250, width: 400, height: 300), on: [screen]),
            "Hanging off the bottom, the title bar is still on the screen"
        )
        XCTAssertFalse(
            FloatingPanelFrames.isReachable(CGRect(x: 100, y: 1060, width: 400, height: 300), on: [screen]),
            "The title bar is above the screen"
        )
        XCTAssertFalse(
            FloatingPanelFrames.isReachable(CGRect(x: 2000, y: 100, width: 400, height: 300), on: [screen]),
            "Entirely to the right of the screen"
        )
        XCTAssertFalse(
            FloatingPanelFrames.isReachable(CGRect(x: 1900, y: 100, width: 400, height: 300), on: [screen]),
            "A sliver 20 points wide is not enough to grab"
        )
        XCTAssertFalse(FloatingPanelFrames.isReachable(CGRect(x: 100, y: 100, width: 400, height: 300), on: []))
    }

    func test_isReachable_countsEveryScreen() {
        let second = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        let frame = CGRect(x: 2000, y: 100, width: 400, height: 300)
        XCTAssertFalse(FloatingPanelFrames.isReachable(frame, on: [screen]))
        XCTAssertTrue(FloatingPanelFrames.isReachable(frame, on: [screen, second]))
    }
}
