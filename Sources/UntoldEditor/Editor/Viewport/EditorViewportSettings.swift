//
//  EditorViewportSettings.swift
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

/// What the viewport header controls: the interaction mode, the tool, the
/// shading, the projection and the camera speed. The tool, the shading and
/// the speed persist across launches; the projection is what the camera was
/// last sent to.
final class EditorViewportSettings: ObservableObject {
    static let shared = EditorViewportSettings(defaults: .standard)

    static let toolKey = "editor.viewport.tool"
    static let shadingKey = "editor.viewport.shading"
    static let cameraSpeedKey = "editor.viewport.cameraSpeed"
    static let speedRange = 1 ... 10
    /// The speed whose multiplier is one: how the camera moved before the control existed.
    static let defaultCameraSpeed = 4

    @Published var interactionMode: InteractionMode = .object
    @Published var tool: TransformTool {
        didSet {
            defaults?.set(tool.rawValue, forKey: Self.toolKey)
        }
    }

    @Published var shading: ViewportShading {
        didSet {
            defaults?.set(shading.rawValue, forKey: Self.shadingKey)
        }
    }

    @Published var projection: ViewportProjection = .perspective
    @Published var cameraSpeed: Int {
        didSet {
            let clamped = min(max(cameraSpeed, Self.speedRange.lowerBound), Self.speedRange.upperBound)
            if cameraSpeed != clamped {
                cameraSpeed = clamped
                return
            }
            defaults?.set(cameraSpeed, forKey: Self.cameraSpeedKey)
        }
    }

    private let defaults: UserDefaults?

    /// `defaults` nil keeps nothing, for tests.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        tool = defaults?.string(forKey: Self.toolKey).flatMap(TransformTool.init(rawValue:)) ?? .move
        shading = defaults?.string(forKey: Self.shadingKey).flatMap(ViewportShading.init(rawValue:)) ?? .lit
        let speed = defaults?.object(forKey: Self.cameraSpeedKey) as? Int ?? Self.defaultCameraSpeed
        cameraSpeed = Self.speedRange.contains(speed) ? speed : Self.defaultCameraSpeed
    }

    /// The factor on the camera's fly, orbit and pan steps.
    var speedMultiplier: Float {
        Self.multiplier(forSpeed: cameraSpeed)
    }

    static func multiplier(forSpeed speed: Int) -> Float {
        Float(speed) / Float(defaultCameraSpeed)
    }
}
