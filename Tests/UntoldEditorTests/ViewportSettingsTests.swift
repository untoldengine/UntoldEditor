//
//  ViewportSettingsTests.swift
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
@testable import UntoldEngine
import XCTest

final class ViewportSettingsTests: XCTestCase {
    func test_settings_persistTheToolTheShadingAndTheSpeed() throws {
        let suite = "ViewportSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = EditorViewportSettings(defaults: defaults)
        XCTAssertEqual(settings.tool, .move)
        XCTAssertEqual(settings.shading, .lit)
        XCTAssertEqual(settings.cameraSpeed, EditorViewportSettings.defaultCameraSpeed)

        settings.tool = .rotate
        settings.show(.normal)
        settings.cameraSpeed = 7

        let reloaded = EditorViewportSettings(defaults: defaults)
        XCTAssertEqual(reloaded.tool, .rotate)
        XCTAssertEqual(reloaded.shading, .normal)
        XCTAssertEqual(reloaded.cameraSpeed, 7)
    }

    func test_cameraSpeed_staysInItsRange_andScalesFromTheDefault() {
        let settings = EditorViewportSettings(defaults: nil)
        settings.cameraSpeed = 42
        XCTAssertEqual(settings.cameraSpeed, 10)
        settings.cameraSpeed = 0
        XCTAssertEqual(settings.cameraSpeed, 1)
        settings.cameraSpeed = EditorViewportSettings.defaultCameraSpeed
        XCTAssertEqual(settings.speedMultiplier, 1)
        settings.cameraSpeed = 8
        XCTAssertEqual(settings.speedMultiplier, 2)
    }

    func test_tools_mapToTheirGizmosAndKeys() {
        XCTAssertNil(TransformTool.select.gizmoMode)
        XCTAssertEqual(TransformTool.move.gizmoMode, .translate)
        XCTAssertEqual(TransformTool.rotate.gizmoMode, .rotate)
        XCTAssertEqual(TransformTool.scale.gizmoMode, .scale)
        XCTAssertEqual(TransformTool.allCases.map(\.shortcut), ["⌥1", "⌥2", "⌥3", "⌥4"])
        // The digits 1 to 4 of the main row, by their macOS virtual key codes.
        XCTAssertEqual(TransformTool.allCases.map(\.keyCode), [18, 19, 20, 21])
        XCTAssertEqual(TransformTool.tool(forKeyCode: 20), .rotate)
        // W, which flies the camera, picks nothing.
        XCTAssertNil(TransformTool.tool(forKeyCode: 13))
    }

    func test_theHeader_offersTheViewsLookedAtMost_fromTheMenusChoices() {
        XCTAssertEqual(TextureDebugOption.viewportChoices, [.lit, .albedo, .normal, .depth, .position])
        XCTAssertTrue(TextureDebugOption.viewportChoices.allSatisfy { TextureDebugOption.allCases.contains($0) })
    }

    func test_show_tellsTheEngine_andTheHeaderFollowsTheMenu() {
        let settings = EditorViewportSettings(defaults: nil)
        let before = TextureDebugOption.current
        defer { TextureDebugOption.current = before }

        settings.show(.roughness)
        XCTAssertEqual(TextureDebugOption.current, .roughness, "the engine draws it")
        XCTAssertEqual(settings.shading, .roughness, "and the header says so, though it does not list it")

        settings.show(.lit)
        XCTAssertEqual(TextureDebugOption.current, .lit)
        XCTAssertEqual(settings.shading, .lit)
    }

    func test_presetViews_lookAtThePivotAlongTheirAxis() {
        let pivot = simd_float3(1, 2, 3)
        XCTAssertEqual(ViewportProjection.top.eye(pivot: pivot, distance: 10), simd_float3(1, 12, 3))
        XCTAssertEqual(ViewportProjection.top.view?.up, simd_float3(0, 0, -1))
        XCTAssertEqual(ViewportProjection.front.eye(pivot: pivot, distance: 10), simd_float3(1, 2, 13))
        XCTAssertEqual(ViewportProjection.right.eye(pivot: pivot, distance: 10), simd_float3(11, 2, 3))
        XCTAssertNil(ViewportProjection.perspective.eye(pivot: pivot, distance: 10))
    }

    func test_framing_fitsTheBoundingSphereInTheFieldOfView() {
        let framing = ViewportFraming.framing(
            minimum: simd_float3(-1, -1, -1),
            maximum: simd_float3(1, 1, 1),
            forward: simd_float3(0, 0, -1),
            fovDegrees: 90
        )
        XCTAssertEqual(framing.target, .zero)
        // The sphere's radius over tan(45°), with the 10% margin.
        XCTAssertEqual(framing.distance, Float(3).squareRoot() * 1.1, accuracy: 0.001)
        XCTAssertEqual(framing.eye.z, framing.distance, accuracy: 0.001)
        XCTAssertEqual(framing.eye.x, 0, accuracy: 0.001)
    }
}
