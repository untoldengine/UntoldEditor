//
//  EditorMainMenuKeeperTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
@testable import UntoldEditor
import XCTest

/// The editor's menu bar stays in place when SwiftUI, or anything else,
/// installs another one.
@MainActor
final class EditorMainMenuKeeperTests: XCTestCase {
    private var menuBefore: NSMenu?

    override func setUp() {
        super.setUp()
        menuBefore = NSApplication.shared.mainMenu
    }

    override func tearDown() {
        NSApplication.shared.mainMenu = menuBefore
        super.tearDown()
    }

    private func turnTheRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }

    func test_theKeeper_installsTheEditorsMenu() {
        let editors = NSMenu(title: "Editor")
        let keeper = EditorMainMenuKeeper(menu: editors)

        XCTAssertTrue(NSApplication.shared.mainMenu === editors)
        XCTAssertEqual(keeper.restorations, 0)
    }

    func test_anotherMenuInstalledLater_isPutAside() {
        let editors = NSMenu(title: "Editor")
        let keeper = EditorMainMenuKeeper(menu: editors)

        NSApplication.shared.mainMenu = NSMenu(title: "SwiftUI")
        turnTheRunLoop()

        XCTAssertTrue(NSApplication.shared.mainMenu === editors)
        XCTAssertEqual(keeper.restorations, 1)
    }

    func test_theEditorsMenuSetAgain_countsAsNothing() {
        let editors = NSMenu(title: "Editor")
        let keeper = EditorMainMenuKeeper(menu: editors)

        NSApplication.shared.mainMenu = editors
        turnTheRunLoop()

        XCTAssertEqual(keeper.restorations, 0)
    }

    func test_everyReplacement_isUndone() {
        let editors = NSMenu(title: "Editor")
        let keeper = EditorMainMenuKeeper(menu: editors)

        for _ in 0 ..< 3 {
            NSApplication.shared.mainMenu = NSMenu(title: "SwiftUI")
            turnTheRunLoop()
        }

        XCTAssertTrue(NSApplication.shared.mainMenu === editors)
        XCTAssertEqual(keeper.restorations, 3)
    }

    func test_withoutAKeeper_anotherMenuStays() {
        let editors = NSMenu(title: "Editor")
        NSApplication.shared.mainMenu = editors
        let other = NSMenu(title: "SwiftUI")

        NSApplication.shared.mainMenu = other
        turnTheRunLoop()

        XCTAssertTrue(NSApplication.shared.mainMenu === other)
    }
}
