//
//  InspectorSectionModelTests.swift
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

final class InspectorSectionModelTests: XCTestCase {
    func test_titles_readAsTheMockupNames() {
        XCTAssertEqual(InspectorSectionModel.title(forComponentName: "Render Component"), "Mesh Renderer")
        XCTAssertEqual(InspectorSectionModel.title(forComponentName: "Transform Component"), "Transform")
        XCTAssertEqual(InspectorSectionModel.title(forComponentName: "Kinetic Component"), "Rigid Body")
        XCTAssertEqual(InspectorSectionModel.title(forComponentName: "Dir Light Component"), "Directional Light")
        XCTAssertEqual(InspectorSectionModel.title(forComponentName: "Splat Twin Component"), "Splat Twin")
    }

    func test_onlyTheTransform_hasResetAndClipboard() {
        XCTAssertTrue(InspectorSectionModel.supportsReset(LocalTransformComponent.self))
        XCTAssertTrue(InspectorSectionModel.supportsClipboard(LocalTransformComponent.self))
        XCTAssertFalse(InspectorSectionModel.supportsReset(RenderComponent.self))
        XCTAssertFalse(InspectorSectionModel.supportsClipboard(PointLightComponent.self))
    }

    func test_axisField_formatsAndParsesNumbers() {
        XCTAssertEqual(AxisNumberField.format(1.5, fractionDigits: 2), "1.50")
        XCTAssertEqual(AxisNumberField.format(-2, fractionDigits: 1), "-2.0")
        XCTAssertEqual(AxisNumberField.parse(" -2,5 "), -2.5)
        XCTAssertNil(AxisNumberField.parse("abc"))
    }
}
