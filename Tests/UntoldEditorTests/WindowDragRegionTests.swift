//
//  WindowDragRegionTests.swift
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

final class WindowDragRegionTests: XCTestCase {
    func test_doubleClick_followsTheSystemTitleBarPreference() {
        XCTAssertEqual(WindowDragRegionView.doubleClickAction(preference: nil), .zoom)
        XCTAssertEqual(WindowDragRegionView.doubleClickAction(preference: "Maximize"), .zoom)
        XCTAssertEqual(WindowDragRegionView.doubleClickAction(preference: "Minimize"), .minimize)
        XCTAssertEqual(WindowDragRegionView.doubleClickAction(preference: "None"), .none)
    }
}
