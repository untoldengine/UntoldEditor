//
//  EditorDockLayoutTests.swift
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

final class EditorDockLayoutTests: XCTestCase {
    private var layout: EditorDockLayout!
    private var bottomPanels: [PanelID] {
        PanelID.available.filter { $0.defaultArea == .bottom }
    }

    override func setUp() {
        super.setUp()
        layout = EditorDockLayout()
    }

    override func tearDown() {
        layout = nil
        super.tearDown()
    }

    // MARK: - Default layout

    func test_default_isTheMockup() {
        XCTAssertEqual(layout.state.left, DockAreaState(tabs: [.hierarchy], length: 250))
        XCTAssertEqual(layout.state.right, DockAreaState(tabs: [.inspector], length: 320))
        XCTAssertEqual(layout.state.bottom.tabs, bottomPanels)
        XCTAssertEqual(layout.state.bottom.selected, .assets)
        XCTAssertEqual(layout.state.bottom.length, 250)
        XCTAssertTrue(EditorDockLayout.isValid(layout.state))
    }

    func test_default_docksEveryDockablePanelOnce() {
        XCTAssertEqual(Set(layout.openPanels), Set(PanelID.available.filter(\.isDockable)))
        XCTAssertEqual(layout.openPanels.count, PanelID.available.filter(\.isDockable).count)
        XCTAssertTrue(layout.isOpen(.viewport))
    }

    // MARK: - Close and open

    func test_closeHierarchy_hidesTheLeftArea_andOpenBringsItBack() {
        layout.close(.hierarchy)

        XCTAssertFalse(layout.isOpen(.hierarchy))
        XCTAssertFalse(layout.isVisible(.left))
        XCTAssertEqual(layout.state.left.length, 250)

        layout.open(.hierarchy)

        XCTAssertEqual(layout.tabs(in: .left), [.hierarchy])
        XCTAssertTrue(layout.isVisible(.left))
    }

    func test_closeConsole_leavesTheBottomArea_andOpenRejoinsItInFront() {
        layout.close(.console)
        XCTAssertFalse(layout.tabs(in: .bottom).contains(.console))

        layout.open(.console)

        XCTAssertEqual(layout.area(of: .console), .bottom)
        XCTAssertEqual(layout.state.bottom.selected, .console)
    }

    func test_closingEveryBottomPanel_hidesTheBottomArea() {
        bottomPanels.forEach(layout.close)
        XCTAssertFalse(layout.isVisible(.bottom))
        XCTAssertNil(layout.state.bottom.selected)
    }

    func test_openRemembersTheAreaAPanelWasClosedFrom() {
        layout.move(.console, to: .left)
        layout.close(.console)

        layout.open(.console)

        XCTAssertEqual(layout.area(of: .console), .left)
        XCTAssertEqual(layout.state.left.selected, .console)
    }

    func test_viewportNeverClosesNorDocks() {
        layout.close(.viewport)
        layout.move(.viewport, to: .left)

        XCTAssertTrue(layout.isOpen(.viewport))
        XCTAssertNil(layout.area(of: .viewport))
        XCTAssertEqual(layout.tabs(in: .left), [.hierarchy])
    }

    func test_closingTheFrontTab_bringsAnotherToFront() throws {
        layout.select(.console)
        layout.close(.console)

        let front = try XCTUnwrap(layout.state.bottom.selected)
        XCTAssertTrue(layout.state.bottom.tabs.contains(front))
    }

    func test_toggleArea_hidesAndShowsTheBottomAreaWithItsFrontTab() {
        layout.select(.console)

        layout.toggleArea(.bottom)
        XCTAssertFalse(layout.isVisible(.bottom))
        XCTAssertTrue(bottomPanels.allSatisfy { layout.isOpen($0) == false })

        layout.toggleArea(.bottom)
        XCTAssertEqual(layout.tabs(in: .bottom), bottomPanels)
        XCTAssertEqual(layout.state.bottom.selected, .console)
    }

    func test_toggleArea_withNothingRememberedOpensTheAreaDefaults() {
        layout.close(.hierarchy)
        layout.toggleArea(.left)
        XCTAssertEqual(layout.tabs(in: .left), [.hierarchy])
    }

    // MARK: - Moving

    func test_moveToAnotherArea_joinsItAsTheLastTabInFront() {
        layout.move(.console, to: .right)

        XCTAssertEqual(layout.tabs(in: .right), [.inspector, .console])
        XCTAssertEqual(layout.state.right.selected, .console)
        XCTAssertFalse(layout.tabs(in: .bottom).contains(.console))
    }

    func test_moveWithinItsOwnArea_onlyBringsItToFront() {
        let before = layout.state
        layout.move(.tasks, to: .bottom)

        XCTAssertEqual(layout.state.bottom.tabs, before.bottom.tabs)
        XCTAssertEqual(layout.state.bottom.selected, .tasks)
    }

    func test_moveTheLastTabOut_hidesItsArea() {
        layout.move(.hierarchy, to: .right)

        XCTAssertFalse(layout.isVisible(.left))
        XCTAssertEqual(layout.tabs(in: .right), [.inspector, .hierarchy])
    }

    // MARK: - Resizing

    func test_resize_appliesTheDragToTheLaidOutLength() {
        layout.resize(.left, delta: 40, currentLength: 250, maximum: 800)
        XCTAssertEqual(layout.state.left.length, 290)
    }

    func test_resize_stopsAtTheMinimumAndTheMaximum() {
        layout.resize(.left, delta: -500, currentLength: 250, maximum: 800)
        XCTAssertEqual(layout.state.left.length, PanelID.hierarchy.minimumSize.width)

        layout.resize(.left, delta: 5000, currentLength: 250, maximum: 800)
        XCTAssertEqual(layout.state.left.length, 800)
    }

    func test_resizeBottom_countsTheTabStripInItsMinimum() {
        layout.resize(.bottom, delta: -1000, currentLength: 250, maximum: 600)
        let tallest = bottomPanels.map(\.minimumSize.height).max() ?? 0
        XCTAssertEqual(layout.state.bottom.length, tallest + DockLayoutGeometry.tabStripHeight)
    }

    func test_clampedLength_showsWhatResizeWouldApply_withoutChangingTheLayout() {
        XCTAssertEqual(layout.clampedLength(for: .left, proposed: 290, maximum: 800), 290)
        XCTAssertEqual(layout.clampedLength(for: .left, proposed: -250, maximum: 800), PanelID.hierarchy.minimumSize.width)
        XCTAssertEqual(layout.clampedLength(for: .left, proposed: 5250, maximum: 800), 800)
        // The minimum wins over a maximum under it, so a small window never squeezes the tabs.
        XCTAssertEqual(layout.clampedLength(for: .left, proposed: 100, maximum: 50), PanelID.hierarchy.minimumSize.width)
        XCTAssertEqual(layout.state.left.length, DockArea.left.defaultLength)
    }

    // MARK: - Focus and reset

    func test_focusViewport_roundTrips() {
        let before = layout.state
        layout.toggleFocusViewport()
        XCTAssertTrue(layout.openPanels.isEmpty)
        XCTAssertTrue(layout.isFocusedOnViewport)

        layout.toggleFocusViewport()
        XCTAssertEqual(layout.state, before)
        XCTAssertFalse(layout.isFocusedOnViewport)
    }

    func test_reset_returnsToTheDefault() {
        layout.close(.hierarchy)
        layout.move(.console, to: .right)
        layout.resize(.right, delta: 100, currentLength: 320, maximum: 900)

        layout.reset()

        XCTAssertEqual(layout.state, EditorDockLayout.defaultState())
    }

    // MARK: - Persistence

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "EditorDockLayoutTests.\(UUID().uuidString)"
        return try (XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }

    func test_layoutSurvivesARelaunch() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = EditorDockLayout(defaults: defaults)
        first.close(.hierarchy)
        first.move(.console, to: .right)
        first.resize(.right, delta: 40, currentLength: 320, maximum: 900)
        first.resizeEnded()

        let second = EditorDockLayout(defaults: defaults)
        XCTAssertEqual(second.state, first.state)

        second.open(.hierarchy)
        XCTAssertEqual(second.area(of: .hierarchy), .left)
    }

    func test_focusIsNotPersisted() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = EditorDockLayout(defaults: defaults)
        first.select(.console)
        first.toggleFocusViewport()

        let second = EditorDockLayout(defaults: defaults)
        XCTAssertTrue(second.isOpen(.hierarchy))
        XCTAssertEqual(second.state.bottom.selected, .console)
        XCTAssertFalse(second.isFocusedOnViewport)
    }

    func test_unreadableOrForeignData_fallsBackToTheDefault() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Data("not a layout".utf8), forKey: EditorDockLayout.defaultsKey)
        XCTAssertEqual(EditorDockLayout(defaults: defaults).state, EditorDockLayout.defaultState())

        var twice = EditorDockLayout.defaultState()
        twice.right.tabs.append(.hierarchy)
        XCTAssertFalse(EditorDockLayout.isValid(twice))

        var viewportDocked = EditorDockLayout.defaultState()
        viewportDocked.left.tabs.append(.viewport)
        XCTAssertFalse(EditorDockLayout.isValid(viewportDocked))

        var noFront = EditorDockLayout.defaultState()
        noFront.bottom.selected = .hierarchy
        XCTAssertFalse(EditorDockLayout.isValid(noFront))
    }

    func test_areasPlaceTheirPanelControlsByTheirWidth() {
        XCTAssertEqual(DockArea.bottom.accessoryPlacement, .inline)
        XCTAssertEqual(DockArea.left.accessoryPlacement, .stacked)
        XCTAssertEqual(DockArea.right.accessoryPlacement, .stacked)
    }

    func test_stateRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(layout.state)
        let decoded = try JSONDecoder().decode(DockLayoutState.self, from: data)
        XCTAssertEqual(decoded, layout.state)
    }
}
