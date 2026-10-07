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

/// The editor's menus stay in the menu bar when SwiftUI, or anything else,
/// installs another one or fills the installed one with its own items.
@MainActor
final class EditorMainMenuKeeperTests: XCTestCase {
    private var menuBefore: NSMenu?
    private var windowsMenuBefore: NSMenu?

    override func setUp() {
        super.setUp()
        menuBefore = NSApplication.shared.mainMenu
        windowsMenuBefore = NSApplication.shared.windowsMenu
    }

    override func tearDown() {
        NSApplication.shared.mainMenu = menuBefore
        NSApplication.shared.windowsMenu = windowsMenuBefore
        super.tearDown()
    }

    /// Turns the run loop until the keeper has looked (two seconds at most, for a
    /// busy machine), or for a moment when nothing is expected to happen.
    private func turnTheRunLoop(until done: (() -> Bool)? = nil) {
        guard let done else {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            return
        }
        let deadline = Date().addingTimeInterval(2)
        repeat {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        } while done() == false && Date() < deadline
    }

    /// A menu bar as the editor builds it: three menus, the last the Window menu.
    private func editorsMenu() -> (menu: NSMenu, items: [NSMenuItem], windows: NSMenu) {
        let menu = NSMenu(title: "Editor")
        let windows = NSMenu(title: "Window")
        for title in ["Untold Engine Editor", "File", "View"] {
            let item = NSMenuItem()
            item.submenu = NSMenu(title: title)
            menu.addItem(item)
        }
        let windowItem = NSMenuItem()
        windowItem.submenu = windows
        menu.addItem(windowItem)
        return (menu, menu.items, windows)
    }

    /// A menu bar as SwiftUI installs it: its own menus, filled in by a delegate.
    private final class FillingDelegate: NSObject, NSMenuDelegate {
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.addItem(withTitle: "Help", action: nil, keyEquivalent: "")
        }
    }

    private func swiftUIsMenu() -> NSMenu {
        let menu = NSMenu(title: "SwiftUI")
        for title in ["Untold Engine Studio", "Edit", "View", "Window", "Help"] {
            let item = NSMenuItem()
            item.submenu = NSMenu(title: title)
            menu.addItem(item)
        }
        return menu
    }

    private func titles(_ menu: NSMenu?) -> [String] {
        menu?.items.map { $0.submenu?.title ?? $0.title } ?? []
    }

    func test_withNoMenuBar_theEditorsMenuIsInstalled() {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()

        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        XCTAssertTrue(NSApplication.shared.mainMenu === editors.menu)
        XCTAssertTrue(keeper.isInPlace)
        XCTAssertTrue(NSApplication.shared.windowsMenu === editors.windows)
        XCTAssertEqual(keeper.restorations, 0)
    }

    func test_aMenuBarInstalledBefore_getsTheEditorsMenusAndKeepsItsIdentity() {
        let swiftUIs = swiftUIsMenu()
        NSApplication.shared.mainMenu = swiftUIs
        let editors = editorsMenu()

        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        XCTAssertTrue(NSApplication.shared.mainMenu === swiftUIs)
        XCTAssertEqual(titles(NSApplication.shared.mainMenu), ["Untold Engine Editor", "File", "View", "Window"])
        XCTAssertTrue(keeper.isInPlace)
        XCTAssertEqual(editors.menu.items.count, 0, "the editor's items moved into the installed bar")
    }

    func test_aMenuBarInstalledLater_getsTheEditorsMenus() {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()
        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        let swiftUIs = swiftUIsMenu()
        NSApplication.shared.mainMenu = swiftUIs
        turnTheRunLoop { keeper.isInPlace }

        XCTAssertTrue(NSApplication.shared.mainMenu === swiftUIs)
        XCTAssertEqual(titles(NSApplication.shared.mainMenu), ["Untold Engine Editor", "File", "View", "Window"])
        XCTAssertEqual(keeper.restorations, 1)
    }

    func test_aMenuBarRefilledWithoutBeingReplaced_isPutBackAfterTheNextEvent() throws {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()
        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)
        let bar = try XCTUnwrap(NSApplication.shared.mainMenu)

        // What a menu bar's owner may do on an update of its own: no setter runs.
        bar.removeAllItems()
        for title in ["Edit", "Help"] {
            bar.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        XCTAssertFalse(keeper.isInPlace)
        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: NSApplication.shared)

        XCTAssertEqual(titles(NSApplication.shared.mainMenu), ["Untold Engine Editor", "File", "View", "Window"])
        XCTAssertEqual(keeper.restorations, 1)
    }

    func test_aMenuBarThatFillsItselfInThroughItsDelegate_isStopped() {
        let swiftUIs = swiftUIsMenu()
        let filling = FillingDelegate()
        swiftUIs.delegate = filling
        NSApplication.shared.mainMenu = swiftUIs
        let editors = editorsMenu()

        _ = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        XCTAssertNil(swiftUIs.delegate)
    }

    func test_theWindowsMenu_staysTheEditors() {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()
        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        let swiftUIs = swiftUIsMenu()
        NSApplication.shared.windowsMenu = swiftUIs.items[3].submenu
        NSApplication.shared.mainMenu = swiftUIs
        turnTheRunLoop { keeper.isInPlace }

        XCTAssertTrue(NSApplication.shared.windowsMenu === editors.windows)
    }

    func test_theEditorsMenusInPlace_countAsNothing() {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()
        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        NotificationCenter.default.post(name: NSApplication.didUpdateNotification, object: NSApplication.shared)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: NSApplication.shared)
        NSApplication.shared.mainMenu = editors.menu
        turnTheRunLoop()

        XCTAssertEqual(keeper.restorations, 0)
    }

    func test_everyReplacement_isUndone() {
        NSApplication.shared.mainMenu = nil
        let editors = editorsMenu()
        let keeper = EditorMainMenuKeeper(menu: editors.menu, windowsMenu: editors.windows)

        for _ in 0 ..< 3 {
            NSApplication.shared.mainMenu = swiftUIsMenu()
            turnTheRunLoop { keeper.isInPlace }
        }

        XCTAssertEqual(titles(NSApplication.shared.mainMenu), ["Untold Engine Editor", "File", "View", "Window"])
        XCTAssertEqual(keeper.restorations, 3)
    }

    func test_withoutAKeeper_anotherMenuBarStays() {
        let editors = editorsMenu()
        NSApplication.shared.mainMenu = editors.menu
        let swiftUIs = swiftUIsMenu()

        NSApplication.shared.mainMenu = swiftUIs
        turnTheRunLoop()

        XCTAssertEqual(titles(NSApplication.shared.mainMenu), ["Untold Engine Studio", "Edit", "View", "Window", "Help"])
    }
}
