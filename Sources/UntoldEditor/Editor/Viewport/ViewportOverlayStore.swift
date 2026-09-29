//
//  ViewportOverlayStore.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import Foundation
import simd
import UntoldEngine

/// What the viewport's overlays take from the scene: how the editor's camera
/// sees the world's axes. It is read after a frame was drawn and published
/// only when it changed, so the navigation gizmo is drawn again only when the
/// camera turned.
final class ViewportOverlayStore: ObservableObject {
    static let shared = ViewportOverlayStore()

    /// The ends of the navigation gizmo, the farthest first; none while the
    /// viewport does not show the editor's camera.
    @Published private(set) var handles: [NavigationGizmoHandle] = []

    /// The shortest time between two readings: the overlays follow the camera
    /// at up to sixty a second, however fast the frames come.
    static let minimumInterval: TimeInterval = 1.0 / 60.0 - 0.002

    private var lastSampleTime: TimeInterval = 0

    init() {}

    /// A frame was drawn. The reading waits for the main queue's next turn:
    /// the scene is the main thread's, and nothing is published from inside
    /// the drawing of a frame. True when a reading was asked for.
    @discardableResult
    func frameWasDrawn(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard time - lastSampleTime >= Self.minimumInterval else {
            return false
        }
        lastSampleTime = time
        DispatchQueue.main.async { [weak self] in
            self?.sample()
        }
        return true
    }

    /// Reads the camera now.
    func sample() {
        // The editor draws over its own camera only; a game camera, playing
        // or as a locked preview, shows what the game will show.
        guard gameMode == false,
              let camera = CameraSystem.shared.activeCamera,
              hasComponent(entityId: camera, componentType: SceneCameraComponent.self),
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera)
        else {
            publish([])
            return
        }
        publish(NavigationGizmoGeometry.handles(viewSpace: cameraComponent.viewSpace))
    }

    private func publish(_ next: [NavigationGizmoHandle]) {
        if Self.differ(handles, next) {
            handles = next
        }
    }

    // MARK: - What counts as a change

    /// Less than this of an arm, a twentieth of a point, is not seen.
    static let handleTolerance: Float = 0.002

    static func differ(_ lhs: [NavigationGizmoHandle], _ rhs: [NavigationGizmoHandle]) -> Bool {
        guard lhs.count == rhs.count else {
            return true
        }
        return zip(lhs, rhs).contains { old, new in
            old.axis != new.axis
                || old.isPositive != new.isPositive
                || simd_reduce_max(simd_abs(old.offset - new.offset)) > handleTolerance
                || abs(old.depth - new.depth) > handleTolerance
        }
    }
}
