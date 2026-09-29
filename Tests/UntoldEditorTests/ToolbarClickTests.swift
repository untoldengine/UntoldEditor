//
//  ToolbarClickTests.swift
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

/// The toolbar row shares the window's title bar, and what lies under the
/// row must not take its clicks. A strip with a background right under it
/// once did: the background reached up into the title bar's safe area.
@MainActor
final class ToolbarClickTests: XCTestCase {
    private final class Clicks {
        var play = 0
        var pause = 0
        var project = 0
        var under = 0
        var control = 0
    }

    /// A window that stays where it is put: off every screen, where the
    /// clicks reach its views and nobody sees it.
    private final class OffscreenWindow: NSWindow {
        override func constrainFrameRect(_ frameRect: NSRect, to _: NSScreen?) -> NSRect {
            frameRect
        }
    }

    private let size = CGSize(width: 1200, height: 700)
    private static let controlHeight: CGFloat = 40
    private var window: NSWindow!
    private var clicks: Clicks!

    override func setUp() async throws {
        try await super.setUp()
        clicks = Clicks()
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
        clicks = nil
        try await super.tearDown()
    }

    /// The editor's window with the toolbar row and, right under it, what the
    /// viewport panel starts with.
    private func show(playState: EditorPlayState = .editing, @ViewBuilder underTheToolbar: () -> some View) {
        let clicks = clicks!
        let content = VStack(spacing: 0) {
            EditorToolbarView(
                projectName: "Game",
                playState: playState,
                buildTarget: .constant(.macOS),
                onSelectProject: { clicks.project += 1 },
                onPlayStop: { clicks.play += 1 },
                onPauseResume: { clicks.pause += 1 },
                onStep: {}
            )
            underTheToolbar()
            Color.editorBackground
            // Far from the toolbar: tells whether this session delivers clicks at all.
            Button {
                clicks.control += 1
            } label: {
                Color.editorBarDark
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        // As the editor's root view does, so the row sits in the title bar.
        // The window gives the content its size, as it does in the editor.
        .ignoresSafeArea(.container, edges: .top)

        window = OffscreenWindow(
            contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        EditorWindowChrome.apply(to: window)
        window.contentView = EditorWindowChrome.hostingView(rootView: content)
        // A view takes the mouse only in a window that is shown.
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        // The views of SwiftUI are made on the run loop's next turns.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// A click as the window receives it from the mouse, at a point measured
    /// from the top left of the window's content.
    private func click(x: CGFloat, y: CGFloat) throws {
        let height = try XCTUnwrap(window.contentView).bounds.height
        let location = NSPoint(x: x, y: height - y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    /// Skips the test in a session that hands a window no clicks, as one
    /// without a screen may: a button that stays silent there says nothing
    /// about the toolbar.
    private func requireClicks() throws {
        try click(x: size.width / 2, y: size.height - Self.controlHeight / 2)
        try XCTSkipIf(clicks.control == 0, "this session delivers no clicks to a window")
    }

    /// The Play button: the first of the three in the middle of the row.
    private var playButton: CGPoint {
        CGPoint(x: size.width / 2 - 30, y: EditorToolbarView.height / 2)
    }

    private var sceneTabs: some View {
        SceneTabStripView(sceneCatalog: ProjectSceneCatalog(), activeSceneURL: nil, onSelectScene: { _ in }, onAddScene: {})
    }

    /// A strip as high as the scene tabs that is one button from side to side.
    private var buttonStrip: some View {
        Button { [clicks] in
            clicks?.under += 1
        } label: {
            Color.editorTabStrip
                .frame(maxWidth: .infinity)
                .frame(height: SceneTabStripView.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func test_theContent_takesNoSafeAreaFromTheWindow() {
        let hostingView = EditorWindowChrome.hostingView(rootView: Color.clear)

        XCTAssertEqual(hostingView.safeAreaRegions, [])
    }

    func test_theWindow_runsItsContentUnderTheTitleBar() {
        show { Color.clear.frame(height: 1) }

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertFalse(window.isMovableByWindowBackground)
        XCTAssertEqual(window.contentView?.frame.height ?? 0, window.frame.height, accuracy: 1, "the content reaches the top of the window")
        XCTAssertLessThan(window.contentLayoutRect.height, window.frame.height, "and the title bar lies over its top")
    }

    func test_play_takesItsClick_withTheSceneTabsUnderTheToolbar() throws {
        show { sceneTabs }
        try requireClicks()

        try click(x: playButton.x, y: playButton.y)

        XCTAssertEqual(clicks.play, 1)
    }

    func test_pause_takesItsClick_whilePlaying() throws {
        show(playState: .playing) { sceneTabs }
        try requireClicks()

        try click(x: playButton.x + 30, y: playButton.y)

        XCTAssertEqual(clicks.pause, 1)
        XCTAssertEqual(clicks.play, 0)
    }

    func test_play_takesItsClick_withABackgroundOfAnyKindUnderTheToolbar() throws {
        show {
            Text("A panel's strip")
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Color.editorTabStrip)
        }
        try requireClicks()

        try click(x: playButton.x, y: playButton.y)

        XCTAssertEqual(clicks.play, 1)
    }

    func test_whatLiesUnderTheToolbar_takesTheClicksOnItself_andNoneOfTheRows() throws {
        show { buttonStrip }
        try requireClicks()

        try click(x: playButton.x, y: EditorToolbarView.height + SceneTabStripView.height / 2)
        XCTAssertEqual(clicks.under, 1)
        XCTAssertEqual(clicks.play, 0)

        try click(x: playButton.x, y: playButton.y)
        XCTAssertEqual(clicks.under, 1, "the row above it is not its own")
        XCTAssertEqual(clicks.play, 1)
    }

    func test_anEmptyPartOfTheRow_pressesNothing() throws {
        show { buttonStrip }
        try requireClicks()

        try click(x: size.width * 0.75, y: playButton.y)

        XCTAssertEqual(clicks.play + clicks.pause + clicks.project + clicks.under, 0)
    }
}
