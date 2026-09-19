//
//  MaterialInspectorTests.swift
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

/// The Material block's arithmetic and its clipboard.
final class MaterialInspectorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        scene = Scene()
        EditorComponentClipboard.shared.clear()
    }

    override func tearDown() {
        EditorComponentClipboard.shared.clear()
        super.tearDown()
    }

    func test_hex_formatsTheColourChannels() {
        XCTAssertEqual(MaterialSnapshot.hex(simd_float4(92 / 255, 224 / 255, 140 / 255, 1)), "#5CE08C")
        XCTAssertEqual(MaterialSnapshot.hex(simd_float4(2, -1, 0, 1)), "#FF0000")
    }

    func test_emission_keepsTheColourAndScalesItsStrength() {
        let scaled = MaterialSnapshot.emissive(forStrength: 0.5, current: simd_float3(1, 0.5, 0), baseColor: simd_float4(0, 0, 1, 1))
        XCTAssertEqual(scaled, simd_float3(0.5, 0.25, 0))

        let fromBase = MaterialSnapshot.emissive(forStrength: 0.8, current: .zero, baseColor: simd_float4(0, 0, 0.5, 1))
        XCTAssertEqual(fromBase, simd_float3(0, 0, 0.8))

        XCTAssertEqual(MaterialSnapshot.emissive(forStrength: 0.3, current: .zero, baseColor: simd_float4(0, 0, 0, 1)), simd_float3(repeating: 0.3))
        XCTAssertEqual(MaterialSnapshot.emissionStrength(of: simd_float3(0.2, 0.9, 0.1)), 0.9)
    }

    func test_slider_mapsBetweenPositionsAndValues() {
        XCTAssertEqual(EditorSlider.fraction(of: 0.25, in: 0 ... 1), 0.25)
        XCTAssertEqual(EditorSlider.fraction(of: 5, in: 0 ... 1), 1)
        XCTAssertEqual(EditorSlider.value(atX: 50, width: 200, in: 0 ... 1), 0.25)
        XCTAssertEqual(EditorSlider.value(atX: -10, width: 200, in: 2 ... 4), 2)
        XCTAssertEqual(EditorSlider.value(atX: 10, width: 0, in: 2 ... 4), 2)
    }

    func test_sphere_spreadsTheHighlightWithRoughness() {
        let smooth = MaterialSphereView.shading(roughness: 0, metallic: 0)
        let rough = MaterialSphereView.shading(roughness: 1, metallic: 0)
        XCTAssertLessThan(smooth.highlightSize, rough.highlightSize)
        XCTAssertGreaterThan(smooth.highlightOpacity, rough.highlightOpacity)
        XCTAssertLessThan(smooth.highlightBlur, rough.highlightBlur)
    }

    func test_materialClipboard_needsACopyAndARenderComponent() {
        let bare = createEntity()
        XCTAssertFalse(EditorComponentClipboard.shared.pasteMaterial(into: bare, meshIndex: 0))

        EditorComponentClipboard.shared.copyMaterial(of: bare, meshIndex: 0)
        XCTAssertNil(EditorComponentClipboard.shared.material, "Nothing to copy without a render component")

        let renderable = createEntity()
        registerComponent(entityId: renderable, componentType: RenderComponent.self)
        EditorComponentClipboard.shared.copyMaterial(of: renderable, meshIndex: 0)
        XCTAssertNotNil(EditorComponentClipboard.shared.material)
        XCTAssertFalse(EditorComponentClipboard.shared.pasteMaterial(into: bare, meshIndex: 0))
        XCTAssertTrue(EditorComponentClipboard.shared.pasteMaterial(into: renderable, meshIndex: 0))
    }
}
