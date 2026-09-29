//
//  EditorNavigationSettingsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
@testable import UntoldEditor
import UntoldEngine
import XCTest

final class EditorNavigationSettingsTests: XCTestCase {
    private func action(shift: Bool = false, command: Bool = false, option: Bool = false) -> CameraDragAction {
        EditorNavigationSettings.dragAction(shiftPressed: shift, commandPressed: command, optionPressed: option)
    }

    // MARK: - Right-button drags

    func test_plainDragLooksAround() {
        XCTAssertEqual(action(), .look)
    }

    func test_shiftPans_commandMoves_optionOrbits() {
        XCTAssertEqual(action(shift: true), .pan)
        XCTAssertEqual(action(command: true), .zoom)
        XCTAssertEqual(action(option: true), .orbit)
    }

    func test_shiftWinsOverCommand_andCommandOverOption() {
        XCTAssertEqual(action(shift: true, command: true), .pan)
        XCTAssertEqual(action(shift: true, option: true), .pan)
        XCTAssertEqual(action(command: true, option: true), .zoom)
        XCTAssertEqual(action(shift: true, command: true, option: true), .pan)
    }

    func test_stylesOnlyDescribeScrolling() {
        for style in CameraNavigationStyle.allCases {
            XCTAssertFalse(style.summary.contains("Drag"), "\(style.title) describes a drag")
        }
        XCTAssertTrue(EditorNavigationSettings.dragSummary.contains("looks around"))
    }

    // MARK: - Persistence

    func test_classic_scrollAlwaysZooms() {
        for shift in [false, true] {
            for command in [false, true] {
                XCTAssertEqual(EditorNavigationSettings.scrollAction(style: .classic, shiftPressed: shift, commandPressed: command), .zoom)
            }
        }
    }

    func test_blender_scrollOrbitsShiftPansCommandZooms() {
        XCTAssertEqual(EditorNavigationSettings.scrollAction(style: .blender, shiftPressed: false, commandPressed: false), .orbit)
        XCTAssertEqual(EditorNavigationSettings.scrollAction(style: .blender, shiftPressed: true, commandPressed: false), .pan)
        XCTAssertEqual(EditorNavigationSettings.scrollAction(style: .blender, shiftPressed: false, commandPressed: true), .zoom)
        // ⇧ wins over ⌘, as for drags.
        XCTAssertEqual(EditorNavigationSettings.scrollAction(style: .blender, shiftPressed: true, commandPressed: true), .pan)
    }

    func test_styleDefaultsToClassicAndPersistsAcrossInstances() throws {
        let suiteName = "EditorNavigationSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(EditorNavigationSettings(defaults: defaults).style, .classic)

        EditorNavigationSettings(defaults: defaults).style = .blender
        XCTAssertEqual(EditorNavigationSettings(defaults: defaults).style, .blender)
        XCTAssertEqual(defaults.string(forKey: EditorNavigationSettings.styleDefaultsKey), "blender")
    }

    func test_unknownPersistedStyleFallsBackToClassic() throws {
        let suiteName = "EditorNavigationSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("maya", forKey: EditorNavigationSettings.styleDefaultsKey)
        XCTAssertEqual(EditorNavigationSettings(defaults: defaults).style, .classic)
    }

    // MARK: - Drag zoom scaling

    #if os(macOS)
        func test_dragZoom_upOrRightZoomsInAndScalesWithDistance() {
            XCTAssertGreaterThan(InputSystem.dragZoomAmount(delta: simd_float2(0, 10), distance: 4), 0)
            XCTAssertGreaterThan(InputSystem.dragZoomAmount(delta: simd_float2(10, 0), distance: 4), 0)
            XCTAssertLessThan(InputSystem.dragZoomAmount(delta: simd_float2(0, -10), distance: 4), 0)

            let near = InputSystem.dragZoomAmount(delta: simd_float2(0, 10), distance: 1)
            let far = InputSystem.dragZoomAmount(delta: simd_float2(0, 10), distance: 10)
            XCTAssertEqual(far / near, 10, accuracy: 0.001)
        }

        func test_dragZoom_nonFiniteDeltaIsIgnored() {
            XCTAssertEqual(InputSystem.dragZoomAmount(delta: simd_float2(.nan, 1), distance: 4), 0)
        }
    #endif
}
