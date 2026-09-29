//
//  ViewportProjection.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd

/// The viewport's projection menu: the free perspective camera, or a preset
/// view along an axis, from either side of it. All of them are the editor's
/// camera; the game camera takes the viewport only while playing.
enum ViewportProjection: String, CaseIterable, Identifiable {
    case perspective
    case top
    case front
    case right
    case bottom
    case back
    case left

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .perspective: return "Perspective"
        case .top: return "Top"
        case .front: return "Front"
        case .right: return "Right"
        case .bottom: return "Bottom"
        case .back: return "Back"
        case .left: return "Left"
        }
    }

    /// The preset views, in the order the menu lists them under the free camera.
    static let presets: [ViewportProjection] = allCases.filter { $0.view != nil }

    /// For a preset view, the direction from the pivot to the eye and which
    /// way is up; nil for the perspective camera, which stays where it is.
    /// From above and from below the world's X runs to the right.
    var view: (direction: simd_float3, up: simd_float3)? {
        switch self {
        case .top: return (simd_float3(0, 1, 0), simd_float3(0, 0, -1))
        case .front: return (simd_float3(0, 0, 1), simd_float3(0, 1, 0))
        case .right: return (simd_float3(1, 0, 0), simd_float3(0, 1, 0))
        case .bottom: return (simd_float3(0, -1, 0), simd_float3(0, 0, 1))
        case .back: return (simd_float3(0, 0, -1), simd_float3(0, 1, 0))
        case .left: return (simd_float3(-1, 0, 0), simd_float3(0, 1, 0))
        case .perspective: return nil
        }
    }

    /// Where the eye goes for a preset view, `distance` from `pivot`.
    func eye(pivot: simd_float3, distance: Float) -> simd_float3? {
        view.map { pivot + $0.direction * distance }
    }
}
