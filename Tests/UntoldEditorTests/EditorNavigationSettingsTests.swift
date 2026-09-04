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
    private func action(
        _ style: CameraNavigationStyle,
        shift: Bool = false,
        command: Bool = false,
        selected: Bool = false
    ) -> CameraDragAction {
        EditorNavigationSettings.dragAction(
            style: style,
            shiftPressed: shift,
            commandPressed: command,
            hasSelection: selected
        )
    }

    // MARK: - Classic style

    func test_classic_plainDragOrbits() {
        XCTAssertEqual(action(.classic), .orbit)
    }

    func test_classic_modifiersStillOrbitWithoutSelection() {
        XCTAssertEqual(action(.classic, shift: true), .orbit)
        XCTAssertEqual(action(.classic, command: true), .orbit)
    }

    func test_classic_shiftWithSelectionIsReservedForEntityManipulation() {
        XCTAssertEqual(action(.classic, shift: true, selected: true), .none)
    }

    // MARK: - Blender style

    func test_blender_plainDragOrbits() {
        XCTAssertEqual(action(.blender), .orbit)
        XCTAssertEqual(action(.blender, selected: true), .orbit)
    }

    func test_blender_shiftDragPansWhenNothingIsSelected() {
        XCTAssertEqual(action(.blender, shift: true), .pan)
    }

    func test_blender_commandDragZooms() {
        XCTAssertEqual(action(.blender, command: true), .zoom)
        XCTAssertEqual(action(.blender, command: true, selected: true), .zoom)
    }

    func test_blender_shiftWithSelectionIsReservedForEntityManipulation() {
        XCTAssertEqual(action(.blender, shift: true, selected: true), .none)
        // Shift wins over Command in that case too.
        XCTAssertEqual(action(.blender, shift: true, command: true, selected: true), .none)
    }

    func test_blender_shiftWinsOverCommand() {
        XCTAssertEqual(action(.blender, shift: true, command: true), .pan)
    }

    // MARK: - Persistence

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
