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

    /// The settings of play the cameras follow; tests put their own here.
    static var playback = EditorPlaybackSettings.shared

    /// The game camera Play shows: the one the scene was authored with when
    /// it is still there, else the active camera when it is a game camera,
    /// else the first game camera of the scene; nil when the scene has none.
    /// Nothing is created: the engine's `findGameCamera()` would, after the
    /// session took its snapshot, and Stop would always find an entity more.
    static func gameCameraForPlay(authored: EntityID?) -> EntityID? {
        let entities = getAllGameEntities()
        if let authored, entities.contains(authored), isGameCamera(authored) {
            return authored
        }
        if let active = CameraSystem.shared.activeCamera, entities.contains(active), isGameCamera(active) {
            return active
        }
        return entities.first(where: isGameCamera)
    }

    /// True from Play to Stop, paused or not.
    static var isPlaying: Bool {
        gameMode || playback.isSessionActive
    }

    /// The camera the viewport shows while editing. From Play to Stop the play
    /// flow owns the camera, so there it is never a preview.
    static var current: ViewportCamera {
        guard isPlaying == false,
              let active = CameraSystem.shared.activeCamera,
              isGameCamera(active)
        else {
            return .editor
        }
        return .game(active)
    }

    /// The camera the keys and the mouse steer now, or nil when they steer
    /// none. While editing it is the editor's, and a game camera shown as a
    /// locked preview stays where it is. While a headset previews the scene it
    /// is the editor's too, which carries the headset: the keys and the mouse
    /// fly it, and the headset sees the scene from there. While playing it is
    /// the camera the viewport shows: the game's, unless View > Steer the
    /// Camera While Playing is off and the game steers it alone, or the
    /// editor's when the View menu keeps the viewport on it.
    static var steered: EntityID? {
        if let active = CameraSystem.shared.activeCamera, isGameCamera(active) {
            return isPlaying && playback.steersCameraWhilePlaying ? active : nil
        }
        return findSceneCamera()
    }

    /// True while the viewport is a locked preview of a game camera, or while
    /// a headset previews the scene: clicks select nothing and the editor
    /// draws none of its overlays, until the editor's camera is chosen again
    /// or the preview ends. The keys and the mouse move nothing in a game
    /// camera's preview; with a headset they fly the editor's camera.
    static var isLockedPreview: Bool {
        current != .editor || isPreviewingOnHeadset()
    }

    /// Whether the scene is previewed on a headset, which the editor's camera
    /// carries then. Tests put their own answer here.
    static var isPreviewingOnHeadset: () -> Bool = { VisionProPreviewState.shared.isPreviewing }

    /// An entity is about to leave the scene. A game camera the viewport is
    /// locked on, or an ancestor of it, which goes with it, gives the viewport
    /// back to the editor's camera first: the engine never clears its active
    /// camera, and every pass of it stops at one that no longer exists. True
    /// when the viewport changed.
    @discardableResult
    static func forget(_ entityId: EntityID) -> Bool {
        guard case let .game(shown) = current, shown == entityId || isAncestor(entityId, of: shown) else {
            return false
        }
        return show(.editor)
    }

    private static func isAncestor(_ entityId: EntityID, of descendant: EntityID) -> Bool {
        var current = descendant
        var depth = 0
        while hasComponent(entityId: current, componentType: ScenegraphComponent.self),
              let parent = getEntityParent(entityId: current), parent != .invalid, depth < 64
        {
            if parent == entityId {
                return true
            }
            current = parent
            depth += 1
        }
        return false
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
