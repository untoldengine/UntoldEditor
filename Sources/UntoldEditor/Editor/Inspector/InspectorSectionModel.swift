//
//  InspectorSectionModel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// What the Inspector shows for each component: its section title and which
/// section actions it has.
enum InspectorSectionModel {
    /// The section title for a component option's name, in the mockup's words.
    static func title(forComponentName name: String) -> String {
        switch name {
        case "Render Component": return "Mesh Renderer"
        case "Transform Component": return "Transform"
        case "Animation Component": return "Animation"
        case "Kinetic Component": return "Rigid Body"
        case "Dir Light Component": return "Directional Light"
        case "Point Light Component": return "Point Light"
        case "Spot Light Component": return "Spot Light"
        case "Area Light Component": return "Area Light"
        case "Camera Component": return "Camera"
        case "Gaussian Component": return "Gaussian Splats"
        case "LOD Component": return "Level of Detail"
        case "Script Component": return "Script"
        default: return name.replacingOccurrences(of: " Component", with: "")
        }
    }

    /// Reset puts a component back to its defaults: the transform, for now.
    static func supportsReset(_ type: Any.Type) -> Bool {
        ObjectIdentifier(type) == ObjectIdentifier(LocalTransformComponent.self)
    }

    /// Copy and Paste carry a component's values to another entity: the
    /// transform, and the material of a mesh renderer.
    static func supportsClipboard(_ type: Any.Type) -> Bool {
        ObjectIdentifier(type) == ObjectIdentifier(LocalTransformComponent.self) || isMeshRenderer(type)
    }

    static func isMeshRenderer(_ type: Any.Type) -> Bool {
        ObjectIdentifier(type) == ObjectIdentifier(RenderComponent.self)
    }
}
