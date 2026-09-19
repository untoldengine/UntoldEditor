//
//  SceneTabTests.swift
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

final class SceneTabTests: XCTestCase {
    private let level1 = ProjectSceneFile(url: URL(fileURLWithPath: "/p/Scenes/Level_01.untoldscene"), name: "Level_01")
    private let level2 = ProjectSceneFile(url: URL(fileURLWithPath: "/p/Scenes/Level_02.untoldscene"), name: "Level_02")

    func test_tabs_followTheCatalogOrder_andMarkTheLoadedScene() {
        let tabs = SceneTab.tabs(catalog: [level1, level2], activeURL: level2.url, isDirty: true)
        XCTAssertEqual(tabs.map(\.name), ["Level_01", "Level_02"])
        XCTAssertEqual(tabs.map(\.isActive), [false, true])
        XCTAssertEqual(tabs.map(\.isDirty), [false, true])
    }

    func test_tabs_putAnUnsavedSceneFirst() {
        let tabs = SceneTab.tabs(catalog: [level1], activeURL: nil, isDirty: false)
        XCTAssertEqual(tabs.map(\.name), ["Untitled Scene", "Level_01"])
        XCTAssertEqual(tabs.first?.isActive, true)
        XCTAssertNil(tabs.first?.url)
    }

    func test_tabs_showALoadedSceneOutsideTheCatalogByItsFileName() {
        let elsewhere = URL(fileURLWithPath: "/tmp/Sandbox.untoldscene")
        let tabs = SceneTab.tabs(catalog: [level1], activeURL: elsewhere, isDirty: true)
        XCTAssertEqual(tabs.map(\.name), ["Sandbox", "Level_01"])
        XCTAssertEqual(tabs.first?.isDirty, true)
        XCTAssertEqual(tabs.last?.isActive, false)
    }

    func test_name_isTheFileNameOrUntitled() {
        XCTAssertEqual(SceneTab.name(for: level1.url), "Level_01")
        XCTAssertEqual(SceneTab.name(for: nil), "Untitled Scene")
    }
}
