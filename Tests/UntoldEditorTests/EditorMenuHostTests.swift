//
//  EditorMenuHostTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import UntoldComponentKit
@testable import UntoldEditor
import XCTest

final class EditorMenuHostTests: XCTestCase {
    private var mainMenu: NSMenu!
    private var host: EditorMenuHost!
    private var probe: MenuProbeExtension!

    override func setUp() {
        super.setUp()
        mainMenu = makeEditorLikeMainMenu()
        host = EditorMenuHost(mainMenuProvider: { [unowned self] in mainMenu })
        probe = MenuProbeExtension()
    }

    private func install() {
        host.install(probe.untoldMenuItems().map { (owner: probe as EditorExtension, menu: $0.menu) })
    }

    private func root(_ title: String) -> NSMenu? {
        mainMenu.items.first { $0.submenu?.title == title }?.submenu
    }

    func test_itemsLandUnderTheirDomainAndNeverCreateOtherRoots() throws {
        install()

        XCTAssertEqual(mainMenu.items.map(\.title), ["App", "File", "View", "Debug", "Tools"])

        let view = try XCTUnwrap(root("View"))
        XCTAssertEqual(view.items.map(\.title), ["View built-in", "", "Preview Twins"], "contributed items follow a separator")
        XCTAssertTrue(view.items[1].isSeparatorItem)

        let debug = try XCTUnwrap(root("Debug"))
        XCTAssertEqual(debug.items.map(\.title), ["Splat Twin"])
        let splatTwin = try XCTUnwrap(debug.items[0].submenu)
        XCTAssertEqual(splatTwin.items.map(\.title), ["Quality", "Reset"])
        XCTAssertEqual(splatTwin.items[0].submenu?.items.map(\.title), ["low", "high"], "a choice is a submenu of radio items")

        XCTAssertEqual(try XCTUnwrap(root("Tools")).items.map(\.title), ["Bake"])
        XCTAssertEqual(try XCTUnwrap(root("File")).items.map(\.title), ["File built-in"], "untouched when nothing targets it")
    }

    func test_removeAllLeavesTheEditorsMenusAsTheyWere() {
        install()
        host.removeAll()

        XCTAssertEqual(mainMenu.items.map(\.title), ["App", "File", "View"])
        XCTAssertEqual(root("View")?.items.map(\.title), ["View built-in"])
        XCTAssertNil(root("View")?.delegate)
    }

    func test_reinstallingAfterAReloadDoesNotDuplicate() {
        install()
        host.removeAll()
        probe = MenuProbeExtension()
        install()

        XCTAssertEqual(mainMenu.items.map(\.title), ["App", "File", "View", "Debug", "Tools"])
        XCTAssertEqual(root("View")?.items.count, 3)
    }

    func test_clickingAToggleFlipsTheWrappedValueAndReports() throws {
        install()
        var reported: [String] = []
        host.onValueChanged = { _, menu in reported.append(menu.identifier) }
        let item = try XCTUnwrap(root("View")?.items.last)

        host.itemClicked(item)

        XCTAssertFalse(probe.preview)
        XCTAssertEqual(reported, ["view/Preview Twins"])
    }

    func test_clickingAChoiceSelectsItAndAnActionJustRuns() throws {
        install()
        var reported: [String] = []
        host.onValueChanged = { _, menu in reported.append(menu.identifier) }
        let splatTwin = try XCTUnwrap(root("Debug")?.items[0].submenu)
        let high = try XCTUnwrap(splatTwin.items[0].submenu?.items[1])

        host.itemClicked(high)
        host.itemClicked(splatTwin.items[1])

        XCTAssertEqual(probe.quality, .high)
        XCTAssertEqual(probe.events, ["reset"])
        XCTAssertEqual(reported, ["debug/Splat Twin/Quality"], "an action has no value to report")
    }

    func test_openingAMenuAsksTheOwnerThenSyncsCheckmarks() throws {
        install()
        let view = try XCTUnwrap(root("View"))
        probe.externalPreviewState = false

        host.menuNeedsUpdate(view)

        XCTAssertEqual(probe.events, ["willOpen"], "asked once per owner")
        XCTAssertEqual(view.items.last?.state, .off, "the checkmark follows what menuWillOpen refreshed")

        let choiceMenu = try XCTUnwrap(root("Debug")?.items[0].submenu?.items[0].submenu)
        host.menuNeedsUpdate(choiceMenu)
        XCTAssertEqual(choiceMenu.items.map(\.state), [.on, .off])
    }

    func test_itemsOfAnExtensionThatIsGoneAreDisabled() throws {
        install()
        let item = try XCTUnwrap(root("View")?.items.last)
        probe = nil

        XCTAssertFalse(host.validateMenuItem(item))
        host.itemClicked(item) // must not crash
    }
}
