//
//  EditorExtensionHostTests.swift
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

final class EditorExtensionHostTests: XCTestCase {
    private var mainMenu: NSMenu!
    private var menuHost: EditorMenuHost!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var host: EditorExtensionHost!

    override func setUp() {
        super.setUp()
        mainMenu = makeEditorLikeMainMenu()
        menuHost = EditorMenuHost(mainMenuProvider: { [unowned self] in mainMenu })
        suiteName = "EditorExtensionHostTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        host = EditorExtensionHost(menuHost: menuHost, defaults: defaults)
        EditorExtensionRegistry.shared.removeAll()
        EditorExtensionRegistry.shared.register(MenuProbeExtension.self, revision: 1)
    }

    override func tearDown() {
        host.unloadAll()
        EditorExtensionRegistry.shared.removeAll()
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private var probe: MenuProbeExtension? {
        host.live.first?.instance as? MenuProbeExtension
    }

    func test_loadBuildsMenusThenAnnouncesLoadAndEachStatefulItem() throws {
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")

        let probe = try XCTUnwrap(probe)
        XCTAssertEqual(probe.events, [
            "load",
            "changed:view/Preview Twins",
            "changed:debug/Splat Twin/Quality",
            "changed:tools/Bake",
        ], "actions hold no state, so they are not announced")
        XCTAssertEqual(mainMenu.items.map(\.title), ["App", "File", "View", "Debug", "Tools"])
        XCTAssertEqual(host.live.first?.menuIdentifiers.count, 4)
    }

    func test_valuesArePersistedPerProjectAndRestoredOnTheNextLoad() throws {
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        let viewItem = try XCTUnwrap(mainMenu.items[2].submenu?.items.last)
        menuHost.itemClicked(viewItem)
        XCTAssertEqual(defaults.object(forKey: "editor.menu.project.view/Preview Twins") as? Bool, false)

        host.unloadAll()
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        XCTAssertEqual(probe?.preview, false, "restored before onLoad")

        host.unloadAll()
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "another-project")
        XCTAssertEqual(probe?.preview, true, "another project starts from the declared default")
    }

    func test_itemsThatOptOutAreNotPersisted() throws {
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        let bake = try XCTUnwrap(mainMenu.items.last?.submenu?.items.first)

        menuHost.itemClicked(bake)

        XCTAssertEqual(probe?.bake, true)
        XCTAssertNil(defaults.object(forKey: "editor.menu.project.tools/Bake"))
    }

    func test_aChoiceSavedForACaseThatNoLongerExistsFallsBackToTheDefault() {
        defaults.set("ultra", forKey: "editor.menu.project.debug/Splat Twin/Quality")
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        XCTAssertEqual(probe?.quality, .low)
    }

    func test_clashesAndEmptyPathsAreRefusedAndReported() {
        EditorExtensionRegistry.shared.register(ClashingExtension.self, revision: 1)

        host.load(typeNames: ["MenuProbeExtension", "ClashingExtension"], projectKey: "project")

        XCTAssertEqual(host.issues.count, 2)
        XCTAssertTrue(host.issues.contains { $0.contains("already declared") })
        XCTAssertTrue(host.issues.contains { $0.contains("no title") })
        // Extensions load in name order, so the first by name keeps a contested path.
        let clashing = host.live.first { $0.name == "ClashingExtension" }
        XCTAssertEqual(clashing?.menuIdentifiers, ["view/Preview Twins", "tools/Unique"])
        let probe = host.live.first { $0.name == "MenuProbeExtension" }
        XCTAssertEqual(probe?.menuIdentifiers, ["debug/Splat Twin/Quality", "debug/Splat Twin/Reset", "tools/Bake"], "the loser keeps its other items")
    }

    func test_unloadAnnouncesAndRemovesTheMenus() throws {
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        let probe = try XCTUnwrap(probe)

        host.unloadAll()

        XCTAssertEqual(probe.events.last, "unload")
        XCTAssertEqual(mainMenu.items.map(\.title), ["App", "File", "View"])
        XCTAssertTrue(host.live.isEmpty)
    }

    func test_editorEventsReachEveryLiveExtension() throws {
        host.load(typeNames: ["MenuProbeExtension"], projectKey: "project")
        let probe = try XCTUnwrap(probe)
        probe.events.removeAll()

        host.sceneDidReset()
        host.playModeDidChange(true)
        host.playModeDidChange(false)

        XCTAssertEqual(probe.events, ["sceneReset", "play:true", "play:false"])
    }
}
