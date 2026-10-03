//
//  PlaySceneFingerprint.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The scene as it would be saved, without where its entities and cameras
/// stand. Two fingerprints that are equal, one from before Play and one from
/// Stop, say that a play session changed nothing but placements, which can
/// be put back without loading the scene again. It works on the saved form,
/// so whatever the engine saves of an entity is compared.
enum PlaySceneFingerprint {
    /// Why a scene has to be loaded again after Play whatever happened in the
    /// session: it holds something whose state is not in what is saved.
    enum Blocker: String, Equatable {
        case animation = "an entity is animated"
        case physics = "an entity moves by physics"
        case codeOrScripts = "an entity carries a script or a code component"
        case streaming = "an entity streams its geometry"
    }

    /// What is left out of an entity: who it is, and where it stands.
    static let placementKeys: Set<String> = ["uuid", "position", "axisOfRotations", "rotation", "scale", "cameraData"]

    /// The fingerprint of a saved scene, from its JSON; nil for data that is
    /// no scene.
    static func fingerprint(ofSceneJSON json: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            return nil
        }
        let entities = root["entities"] as? [[String: Any]] ?? []

        // An entity gets a new identifier each time the scene is saved, so a
        // parent is named by its place in the list.
        var places: [String: Int] = [:]
        for (index, entity) in entities.enumerated() {
            if let uuid = entity["uuid"] as? String {
                places[uuid] = index
            }
        }

        root["entities"] = entities.map { entity -> [String: Any] in
            var kept = entity.filter { placementKeys.contains($0.key) == false }
            if let parent = entity["parentUUID"] as? String {
                kept["parentUUID"] = places[parent] ?? -1
            }
            if var instance = entity["assetInstance"] as? [String: Any],
               let overrides = instance["overrides"] as? [[String: Any]]
            {
                instance["overrides"] = overrides.map { $0.filter { $0.key != "transform" } }
                kept["assetInstance"] = instance
            }
            return kept
        }
        return try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    }

    /// What in a saved scene only loading it again brings back, if anything.
    static func blocker(inSceneJSON json: Data) -> Blocker? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
              let entities = root["entities"] as? [[String: Any]]
        else {
            return nil
        }
        for entity in entities {
            if entity["hasAnimationComponent"] as? Bool == true || isFilled(entity["animations"]) || isFilled(entity["animationAssets"]) {
                return .animation
            }
            if entity["hasKineticComponent"] as? Bool == true {
                return .physics
            }
            if isFilled(entity["customComponents"]) {
                return .codeOrScripts
            }
            if entity["hasStreamingComponent"] as? Bool == true || entity["streamingData"] is [String: Any] {
                return .streaming
            }
        }
        return nil
    }

    private static func isFilled(_ value: Any?) -> Bool {
        if let list = value as? [Any] {
            return list.isEmpty == false
        }
        if let table = value as? [String: Any] {
            return table.isEmpty == false
        }
        return false
    }
}
