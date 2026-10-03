//
//  SnapSettingsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class SnapSettingsTests: XCTestCase {
    func test_quantize_landsOnTheNearestStep() {
        XCTAssertEqual(EditorSnapSettings.quantize(0.37, step: 0.25), 0.25)
        XCTAssertEqual(EditorSnapSettings.quantize(0.38, step: 0.25), 0.5)
        XCTAssertEqual(EditorSnapSettings.quantize(-0.37, step: 0.25), -0.25)
        XCTAssertEqual(EditorSnapSettings.quantize(7, step: 15), 0)
        XCTAssertEqual(EditorSnapSettings.quantize(8, step: 15), 15)
        XCTAssertEqual(EditorSnapSettings.quantize(0.37, step: 0), 0.37, "No step, no snapping")
    }

    func test_steps_followTheMasterSwitchAndEachKindsOwn() {
        let snap = EditorSnapSettings(defaults: nil)
        XCTAssertNil(snap.step(for: .translate), "Off by default")
        XCTAssertEqual(snap.snapped(0.37, for: .translate), 0.37)

        snap.isEnabled = true
        XCTAssertEqual(snap.step(for: .translate), 0.5)
        XCTAssertEqual(snap.step(for: .rotate), 15)
        XCTAssertEqual(snap.step(for: .scale), 0.25)
        XCTAssertNil(snap.step(for: .none))
        XCTAssertEqual(snap.snapped(0.37, for: .translate), 0.5)

        snap.snapsRotate = false
        XCTAssertNil(snap.step(for: .rotate))
        XCTAssertEqual(snap.snapped(7, for: .rotate), 7)
    }

    func test_summary_showsTheGridStepWhileOn() {
        let snap = EditorSnapSettings(defaults: nil)
        XCTAssertEqual(snap.summary, "Snap off")
        snap.isEnabled = true
        XCTAssertEqual(snap.summary, "Snap 0.5 m")
        snap.gridStep = 1
        XCTAssertEqual(snap.summary, "Snap 1 m")
        XCTAssertEqual(EditorSnapSettings.format(0.25), "0.25")
    }

    func test_settings_persist_andIgnoreStepsOutsideTheChoices() throws {
        let suite = "SnapSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let snap = EditorSnapSettings(defaults: defaults)
        snap.isEnabled = true
        snap.snapsScale = false
        snap.gridStep = 0.1
        snap.rotationStep = 45
        defaults.set(Float(0.3), forKey: EditorSnapSettings.keyPrefix + "scaleStep")

        let reloaded = EditorSnapSettings(defaults: defaults)
        XCTAssertTrue(reloaded.isEnabled)
        XCTAssertFalse(reloaded.snapsScale)
        XCTAssertEqual(reloaded.gridStep, 0.1)
        XCTAssertEqual(reloaded.rotationStep, 45)
        XCTAssertEqual(reloaded.scaleStep, 0.25, "A step outside the choices falls back")
    }
}
