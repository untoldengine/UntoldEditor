//
//  ViewportCamera.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// A camera the viewport can show while editing: the editor's own, which the
/// mouse and the keys steer, or a camera of the game as a locked preview.
enum ViewportCamera: Equatable {
    case editor
    case game(EntityID)
}

/// A game camera of the scene, as the View menu lists it.
struct GameCameraChoice: Equatable, Identifiable {
    let entityId: EntityID
    let name: String

    var id: EntityID {
        entityId
    }
}

/// The viewport's cameras, read from the scene and from the engine's active
/// camera, so nothing is kept that a scene load or the play flow could leave
/// stale. Nothing here creates a camera: the engine's `findGameCamera()` does,
/// and makes it the active one, so the editor never asks it which cameras exist.
enum ViewportCameras {
    /// Whether the entity is a camera of the game, not the editor's own.
    static func isGameCamera(_ entityId: EntityID) -> Bool {
        hasComponent(entityId: entityId, componentType: CameraComponent.self)
            && hasComponent(entityId: entityId, componentType: SceneCameraComponent.self) == false
    }

    /// The scene's game cameras in scene order, under the names the hierarchy shows.
    static func gameCameras() -> [GameCameraChoice] {
        getAllGameEntities().filter(isGameCamera).map { entityId in
            let name = getEntityName(entityId: entityId)
            return GameCameraChoice(entityId: entityId, name: name.isEmpty ? "Camera" : name)
        }
    }

    /// The camera the viewport shows while editing. While the game runs the
    /// play flow owns the camera, so there it is never a preview.
    static var current: ViewportCamera {
        guard gameMode == false,
              let active = CameraSystem.shared.activeCamera,
              isGameCamera(active)
        else {
            return .editor
        }
        return .game(active)
    }

    /// True while the viewport is a locked preview of a game camera: the mouse
    /// and the keys move nothing, clicks select nothing and the editor draws
    /// none of its overlays, until the editor's camera is chosen again.
    static var isLockedPreview: Bool {
        current != .editor
    }

    /// Shows a camera in the viewport. False, changing nothing, for a game
    /// camera that is no longer in the scene.
    @discardableResult
    static func show(_ camera: ViewportCamera) -> Bool {
        switch camera {
        case .editor:
            setCamera(.active(findSceneCamera()))
            return true
        case let .game(entityId):
            guard isGameCamera(entityId) else { return false }
            setCamera(.active(entityId))
            return true
        }
    }
}
