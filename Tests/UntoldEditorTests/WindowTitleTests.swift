//
//  WindowTitleTests.swift
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

final class WindowTitleTests: XCTestCase {
    func testTitleWithoutProjectShowsAppNameAndVersion() {
        XCTAssertEqual(AppDelegate.windowTitle(projectName: nil, version: "0.18.0"), "Untold Engine Editor v0.18.0")
        XCTAssertEqual(AppDelegate.windowTitle(projectName: "", version: "0.18.0"), "Untold Engine Editor v0.18.0")
    }

    func testTitleWithProjectShowsProjectNameThenEditorNameAndVersion() {
        XCTAssertEqual(AppDelegate.windowTitle(projectName: "MyGame", version: "0.18.0"), "MyGame - Untold Engine Editor v0.18.0")
    }

    func testProjectNameIsDerivedFromGameDataPath() {
        let store = EditorAssetBasePath.shared
        let previous = store.basePath
        defer { store.basePath = previous }

        store.basePath = URL(fileURLWithPath: "/tmp/Projects/MyGame/Sources/MyGame/GameData")
        XCTAssertEqual(AppDelegate.windowTitle(projectName: store.projectName, version: "0.18.0"), "MyGame - Untold Engine Editor v0.18.0")

        store.basePath = nil
        XCTAssertEqual(AppDelegate.windowTitle(projectName: store.projectName, version: "0.18.0"), "Untold Engine Editor v0.18.0")
    }
}
