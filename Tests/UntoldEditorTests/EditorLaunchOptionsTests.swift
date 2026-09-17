//
//  EditorLaunchOptionsTests.swift
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

final class EditorLaunchOptionsTests: XCTestCase {
    func test_openProjectTakesTheFolderThatFollowsTheFlag() {
        let url = EditorLaunchOptions.projectToOpen(arguments: ["UntoldEditor", "--open-project", "/Projects/SplatTwin/"])
        XCTAssertEqual(url?.path, "/Projects/SplatTwin")
    }

    func test_withoutTheFlagOrItsValueNothingOpens() {
        XCTAssertNil(EditorLaunchOptions.projectToOpen(arguments: ["UntoldEditor"]))
        XCTAssertNil(EditorLaunchOptions.projectToOpen(arguments: ["UntoldEditor", "--open-project"]))
        XCTAssertNil(EditorLaunchOptions.projectToOpen(arguments: ["UntoldEditor", "--open-project", "--verbose"]))
    }
}
