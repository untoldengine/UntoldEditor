//
//  PlaySceneFingerprintTests.swift
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

/// The fingerprint of a saved scene leaves out who an entity is and where it
/// stands, and nothing else.
final class PlaySceneFingerprintTests: XCTestCase {
    /// A saved scene of two entities, the second under the first.
    private func sceneJSON(
        firstUUID: String = "A0000000-0000-0000-0000-000000000001",
        secondUUID: String = "A0000000-0000-0000-0000-000000000002",
        position: [Double] = [1, 2, 3],
        name: String = "Crate",
        roughness: Double = 0.5,
        exposure: Double = 1,
        overrideTransform: [Double] = [0, 0, 0],
        overrideVisibility: Bool = true,
        extra: [String: Any] = [:]
    ) throws -> Data {
        var first: [String: Any] = [
            "uuid": firstUUID,
            "name": "Root",
            "position": [0, 0, 0],
            "rotation": [0, 0, 0, 1],
            "axisOfRotations": [0, 0, 0],
            "scale": [1, 1, 1],
            "hasLocalTransformComponent": true,
            "assetInstance": [
                "assetName": "building",
                "importMode": "preserveHierarchy",
                "overrides": [[
                    "nodePath": "/building/door",
                    "transform": ["position": overrideTransform],
                    "visibility": overrideVisibility,
                ]],
            ],
        ]
        for (key, value) in extra {
            first[key] = value
        }
        let second: [String: Any] = [
            "uuid": secondUUID,
            "parentUUID": firstUUID,
            "name": name,
            "position": position,
            "rotation": [0, 0, 0, 1],
            "axisOfRotations": [0, 0, 0],
            "scale": [1, 1, 1],
            "materialData": ["roughnessValue": roughness],
            "cameraData": ["eye": position, "target": [0, 0, 0], "up": [0, 1, 0]],
        ]
        let scene: [String: Any] = [
            "schemaVersion": 2,
            "entities": [first, second],
            "toneMapping": ["exposure": exposure],
        ]
        return try JSONSerialization.data(withJSONObject: scene)
    }

    private func fingerprint(_ json: Data) throws -> Data {
        try XCTUnwrap(PlaySceneFingerprint.fingerprint(ofSceneJSON: json))
    }

    func test_theSameScene_savedTwice_hasOneFingerprint() throws {
        // An entity gets a new identifier each time the scene is saved.
        let again = try sceneJSON(
            firstUUID: "B0000000-0000-0000-0000-000000000001",
            secondUUID: "B0000000-0000-0000-0000-000000000002"
        )

        XCTAssertEqual(try fingerprint(sceneJSON()), try fingerprint(again))
    }

    func test_whereAnEntityStands_isNotInTheFingerprint() throws {
        let moved = try sceneJSON(position: [9, 8, 7])

        XCTAssertEqual(try fingerprint(sceneJSON()), try fingerprint(moved))
    }

    func test_whereANodeOfAnAssetStands_isNotInTheFingerprint() throws {
        let moved = try sceneJSON(overrideTransform: [4, 0, 0])

        XCTAssertEqual(try fingerprint(sceneJSON()), try fingerprint(moved))
    }

    func test_whatElseAnEntityHolds_isInTheFingerprint() throws {
        let original = try fingerprint(sceneJSON())

        XCTAssertNotEqual(original, try fingerprint(sceneJSON(name: "Barrel")), "its name")
        XCTAssertNotEqual(original, try fingerprint(sceneJSON(roughness: 0.9)), "its material")
        XCTAssertNotEqual(original, try fingerprint(sceneJSON(overrideVisibility: false)), "whether a node of its asset shows")
        XCTAssertNotEqual(original, try fingerprint(sceneJSON(extra: ["castsShadow": false])), "a field it did not have")
    }

    func test_whatTheSceneHolds_isInTheFingerprint() throws {
        XCTAssertNotEqual(try fingerprint(sceneJSON()), try fingerprint(sceneJSON(exposure: 2)))
    }

    func test_whoTheParentIs_isInTheFingerprint_byItsPlace() throws {
        let original = try JSONSerialization.jsonObject(with: sceneJSON()) as? [String: Any]
        var entities = try XCTUnwrap(original?["entities"] as? [[String: Any]])
        entities[1]["parentUUID"] = nil
        var orphaned = try XCTUnwrap(original)
        orphaned["entities"] = entities

        XCTAssertNotEqual(
            try fingerprint(sceneJSON()),
            try fingerprint(JSONSerialization.data(withJSONObject: orphaned))
        )
    }

    func test_anEntityMore_changesTheFingerprint() throws {
        let original = try JSONSerialization.jsonObject(with: sceneJSON()) as? [String: Any]
        var entities = try XCTUnwrap(original?["entities"] as? [[String: Any]])
        entities.append(["uuid": "A0000000-0000-0000-0000-000000000003", "name": "Spawned"])
        var grown = try XCTUnwrap(original)
        grown["entities"] = entities

        XCTAssertNotEqual(
            try fingerprint(sceneJSON()),
            try fingerprint(JSONSerialization.data(withJSONObject: grown))
        )
    }

    func test_whatIsNoScene_hasNoFingerprint() {
        XCTAssertNil(PlaySceneFingerprint.fingerprint(ofSceneJSON: Data("not a scene".utf8)))
        XCTAssertNil(PlaySceneFingerprint.fingerprint(ofSceneJSON: Data("[1, 2]".utf8)))
    }

    // MARK: - What only loading the scene again brings back

    func test_aSceneOfThingsThatStand_hasNoBlocker() throws {
        XCTAssertNil(try PlaySceneFingerprint.blocker(inSceneJSON: sceneJSON()))
        XCTAssertNil(try PlaySceneFingerprint.blocker(inSceneJSON: sceneJSON(extra: [
            "hasAnimationComponent": false,
            "hasKineticComponent": false,
            "animations": [String](),
            "customComponents": [String: String](),
        ])))
    }

    func test_whatMovesByItself_blocks() throws {
        let cases: [([String: Any], PlaySceneFingerprint.Blocker)] = [
            (["hasAnimationComponent": true], .animation),
            (["animations": ["file:///walk.usdz"]], .animation),
            (["animationAssets": [["kind": "animation", "path": "Animations/walk.usdz"]]], .animation),
            (["hasKineticComponent": true], .physics),
            (["customComponents": ["Spinner": "e30="]], .codeOrScripts),
            (["hasStreamingComponent": true], .streaming),
            (["streamingData": ["radius": 10]], .streaming),
        ]
        for (extra, expected) in cases {
            XCTAssertEqual(try PlaySceneFingerprint.blocker(inSceneJSON: sceneJSON(extra: extra)), expected, "\(extra.keys.sorted())")
        }
    }
}
