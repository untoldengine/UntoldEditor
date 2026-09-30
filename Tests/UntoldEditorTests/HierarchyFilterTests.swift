//
//  HierarchyFilterTests.swift
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

final class HierarchyFilterTests: XCTestCase {
    // Rig > Rig_Lights > Spot_1, and Rig > Camera. The ids are arbitrary.
    private let rig = EntityID(1)
    private let lights = EntityID(2)
    private let camera = EntityID(3)
    private let spot = EntityID(4)

    private func visible(_ query: String) -> Set<EntityID>? {
        let children: [EntityID: [EntityID]] = [rig: [lights, camera], lights: [spot]]
        let names: [EntityID: String] = [rig: "Rig", lights: "Rig_Lights", camera: "Camera", spot: "Spot_1"]
        return HierarchyFilter.visibleEntities(matching: query, roots: [rig], children: { children[$0] ?? [] }, name: { names[$0] ?? "" })
    }

    func test_blankQuery_filtersNothing() {
        XCTAssertNil(visible(""))
        XCTAssertNil(visible("   "))
    }

    func test_match_keepsTheAncestorsThatLeadToIt() {
        XCTAssertEqual(visible("spot"), [rig, lights, spot])
    }

    func test_match_showsEverythingUnderIt() {
        XCTAssertEqual(visible("lights"), [rig, lights, spot])
    }

    func test_matchIsCaseInsensitive() {
        XCTAssertEqual(visible("CAMERA"), [rig, camera])
    }

    func test_noMatch_showsNothing() {
        XCTAssertEqual(visible("zzz"), [])
    }
}
