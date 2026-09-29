//
//  PlaySessionState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import simd
import UntoldEngine

/// What Play keeps of the scene so that Stop can put it back in place: which
/// entities there were, and where they and the cameras stood.
///
/// Loading the scene again is what always brings it back, and what Stop did
/// before; it destroys every entity and reads every asset again, which for a
/// large scene is a long wait, and it forgets the selection and the undo
/// history, since the entities come back as new ones. When a session moved
/// nothing but where things stand, putting those back is enough. Whether it
/// did is not guessed: the scene is saved again at Stop and compared, apart
/// from the placements, with how it was saved at Play.
struct PlaySessionState {
    /// Where an entity stands in its parent.
    struct Placement: Equatable {
        var position: simd_float3
        var rotation: simd_quatf
        var scale: simd_float3
    }

    /// Why the scene is loaded again at Stop instead of being put back in place.
    enum ReasonToLoadAgain: Equatable, CustomStringConvertible {
        case holds(PlaySceneFingerprint.Blocker)
        case entitiesChanged
        case dataChanged
        case cannotBeCompared

        var description: String {
            switch self {
            case let .holds(blocker): return blocker.rawValue
            case .entitiesChanged: return "entities were added or removed while playing"
            case .dataChanged: return "the scene's data changed while playing"
            case .cannotBeCompared: return "the scene could not be compared with how it was"
            }
        }
    }

    /// The game's entities that were alive at Play.
    let entities: Set<EntityID>
    let placements: [EntityID: Placement]
    let cameras: [EntityID: CameraPlacement]
    /// The scene as saved at Play, without the placements; nil when it could
    /// not be taken.
    let fingerprint: Data?
    /// What in the scene only loading it again brings back, if anything.
    let blocker: PlaySceneFingerprint.Blocker?

    // MARK: - At Play

    /// Takes the state of the scene as it stands, with `saved` being the
    /// scene as the engine saved it just now.
    static func capture(saved: SceneData) -> PlaySessionState {
        let json = try? JSONEncoder().encode(saved)
        let alive = getAllGameEntities()

        var placements: [EntityID: Placement] = [:]
        var cameras: [EntityID: CameraPlacement] = [:]
        for entityId in alive {
            if let local = scene.get(component: LocalTransformComponent.self, for: entityId) {
                placements[entityId] = Placement(position: local.position, rotation: local.rotation, scale: local.scale)
            }
            if let camera = CameraPlacement.capture(of: entityId) {
                cameras[entityId] = camera
            }
        }

        return PlaySessionState(
            entities: Set(alive),
            placements: placements,
            cameras: cameras,
            fingerprint: json.flatMap(PlaySceneFingerprint.fingerprint(ofSceneJSON:)),
            blocker: json.flatMap(PlaySceneFingerprint.blocker(inSceneJSON:))
        )
    }

    // MARK: - At Stop

    /// Why the scene has to be loaded again, with `saved` being the scene as
    /// the engine saves it now; nil when putting the placements back brings
    /// the scene back whole.
    func reasonToLoadAgain(saved: SceneData) -> ReasonToLoadAgain? {
        if let blocker {
            return .holds(blocker)
        }
        guard Set(getAllGameEntities()) == entities else {
            return .entitiesChanged
        }
        guard let fingerprint,
              let json = try? JSONEncoder().encode(saved),
              let now = PlaySceneFingerprint.fingerprint(ofSceneJSON: json)
        else {
            return .cannotBeCompared
        }
        return now == fingerprint ? nil : .dataChanged
    }

    /// Puts every entity and camera back where it stood at Play. Only what
    /// moved is touched, so an entity that stood still keeps its place in a
    /// static batch. Returns how many were put back.
    @discardableResult
    func restoreInPlace() -> Int {
        var restored = 0
        for (entityId, camera) in cameras where CameraPlacement.capture(of: entityId) != camera {
            camera.apply(to: entityId)
            restored += 1
        }
        for (entityId, placement) in placements {
            guard let local = scene.get(component: LocalTransformComponent.self, for: entityId) else {
                continue
            }
            var moved = false
            if local.position != placement.position {
                translateTo(entityId: entityId, position: placement.position)
                moved = true
            }
            if local.rotation != placement.rotation {
                rotateTo(entityId: entityId, rotation: placement.rotation)
                moved = true
            }
            if local.scale != placement.scale {
                scaleTo(entityId: entityId, scale: placement.scale)
                moved = true
            }
            if moved, cameras[entityId] == nil {
                restored += 1
            }
        }
        return restored
    }
}
