//
//  ViewportShading.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// What the viewport draws: the lit scene, or one of the engine's debug views.
enum ViewportShading: String, CaseIterable, Identifiable {
    case lit
    case albedo
    case normals
    case depth
    case position

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .lit: return "Lit"
        case .albedo: return "Albedo"
        case .normals: return "Normals"
        case .depth: return "Depth"
        case .position: return "Position"
        }
    }

    /// The engine's debug view behind each shading.
    var debugView: RenderDebugViewMode {
        switch self {
        case .lit: return .lit
        case .albedo: return .albedo
        case .normals: return .normal
        case .depth: return .depth
        case .position: return .position
        }
    }
}
