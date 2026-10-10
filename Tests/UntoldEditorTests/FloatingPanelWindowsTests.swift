//
//  FloatingPanelWindowsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import SwiftUI
@testable import UntoldEditor
import XCTest

/// The windows of the floating panels beside a real editor window, never
/// ordered front: what the layout says floats has a window, what docks or
/// closes loses it, and the window's own close, Dock and moves reach the layout.
@MainActor
final class FloatingPanelWindowsTests: XCTestCase {
    private var layout: EditorDockLayout!
    private var parent: NSWindow!
    private var windows: FloatingPanelWindows!
    private let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1440)]

    override func setUp() {
        super.setUp()
        layout = EditorDockLayout()
        parent = NSWindow(
            contentRect: CGRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        parent.isReleasedWhenClosed = false
        windows = FloatingPanelWindows(layout: layout, screens: { [screens] in screens }, ordersFront: false)
    }

    override func tearDown() {
        windows.closeAll()
        windows = nil
        parent.close()
        parent = nil
        layout = nil
        super.tearDown()
    }

    private func content(_ panel: PanelID, withAccessories: Bool = false) -> FloatingPanelContent {
        FloatingPanelContent(
            panel: panel,
            content: AnyView(Text(panel.title)),
            accessories: withAccessories ? AnyView(Text("Filter")) : nil
        )
    }

    private func sync(withAccessories: Bool = false) {
        windows.sync(panels: layout.floatingPanels, parent: parent) { panel in
            content(panel, withAccessories: withAccessories)
        }
    }

    private func window(of panel: PanelID) throws -> NSWindow {
        try XCTUnwrap(windows.windows[panel]).window
    }

    func test_aFloatingPanel_getsAFloatingWindowTitledAfterIt_atTheDefaultFrame() throws {
        layout.float(.console)
        sync()

        let window = try window(of: .console)
        XCTAssertEqual(window.title, "Console")
        XCTAssertEqual(window.level, .floating, "Above the editor window on any screen")
        XCTAssertTrue(window.hidesOnDeactivate, "Not above other apps")
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary), "Shows beside a full-screen editor")
        XCTAssertFalse(window.isExcludedFromWindowsMenu, "The Window menu finds it on another screen")
        XCTAssertNil(window.parent, "Not a child window: a child cannot leave its parent's screen")
        XCTAssertEqual(window.contentMinSize, PanelID.console.minimumSize)
        XCTAssertEqual(window.frame, FloatingPanelFrames.defaultFrame(for: .console, beside: parent.frame, index: 0))
        XCTAssertFalse(window.isVisible, "Tests do not order windows front")
    }

    func test_twoFloatingPanels_cascade_andSyncingAgainKeepsTheirWindows() throws {
        layout.float(.console)
        layout.float(.tasks)
        sync()
        let console = try window(of: .console)
        let tasks = try window(of: .tasks)
        XCTAssertEqual(tasks.frame, FloatingPanelFrames.defaultFrame(for: .tasks, beside: parent.frame, index: 1))

        sync()
        XCTAssertTrue(try window(of: .console) === console)
        XCTAssertTrue(try window(of: .tasks) === tasks)
        XCTAssertEqual(windows.windows.count, 2)
    }

    func test_eachSync_handsTheWindowTheCurrentContent() throws {
        layout.float(.console)
        sync()
        XCTAssertNil(try XCTUnwrap(windows.windows[.console]).content.accessories)

        sync(withAccessories: true)
        XCTAssertNotNil(try XCTUnwrap(windows.windows[.console]).content.accessories)
    }

    func test_dockingThePanel_closesItsWindow() throws {
        layout.float(.console)
        sync()
        let window = try window(of: .console)

        layout.dock(.console)
        sync()

        XCTAssertNil(windows.windows[.console])
        XCTAssertNil(window.delegate, "Closed quietly: its close is not reported as the user's")
        XCTAssertEqual(layout.area(of: .console), .bottom)
    }

    func test_theDockButton_docksThePanel() throws {
        layout.float(.console)
        sync()

        try XCTUnwrap(windows.windows[.console]).dock()

        XCTAssertFalse(layout.isFloating(.console))
        XCTAssertEqual(layout.area(of: .console), .bottom)
        XCTAssertEqual(layout.state.bottom.selected, .console)
    }

    func test_closingTheWindow_closesThePanel_whichComesBackDocked() throws {
        layout.float(.console)
        sync()
        let window = try window(of: .console)

        window.close()

        XCTAssertFalse(layout.isFloating(.console))
        XCTAssertFalse(layout.isOpen(.console))
        XCTAssertNil(windows.windows[.console])

        layout.open(.console)
        XCTAssertEqual(layout.area(of: .console), .bottom)
    }

    func test_movingOrResizingTheWindow_isRemembered_andReusedNextTime() throws {
        layout.float(.console)
        sync()
        let frame = CGRect(x: 300, y: 300, width: 700, height: 400)

        try window(of: .console).setFrame(frame, display: false)
        XCTAssertEqual(layout.floatingFrame(of: .console), frame)

        layout.dock(.console)
        sync()
        layout.float(.console)
        sync()
        XCTAssertEqual(try window(of: .console).frame, frame)
    }

    func test_aRememberedFrameOffEveryScreen_opensAtTheDefault() throws {
        layout.float(.console)
        layout.setFloatingFrame(CGRect(x: 5000, y: 5000, width: 400, height: 300), of: .console)

        sync()

        XCTAssertEqual(try window(of: .console).frame, FloatingPanelFrames.defaultFrame(for: .console, beside: parent.frame, index: 0))
    }

    func test_closingTheEditorWindow_closesTheFloatingOnes_andLeavesTheLayoutAlone() throws {
        layout.float(.console)
        sync()
        let window = try window(of: .console)

        parent.close()

        let deadline = Date().addingTimeInterval(2)
        while windows.windows.isEmpty == false, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(windows.windows.isEmpty)
        XCTAssertNil(window.delegate)
        XCTAssertTrue(layout.isFloating(.console), "The panel floats again at the next launch")
    }

    func test_closeAll_leavesTheLayoutAlone() {
        layout.float(.console)
        sync()

        windows.closeAll()

        XCTAssertTrue(windows.windows.isEmpty)
        XCTAssertTrue(layout.isFloating(.console))
    }
}
