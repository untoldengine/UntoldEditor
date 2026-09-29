//
//  NavigationAxis.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
import SwiftUI

/// An axis of the world, as the navigation gizmo shows it.
enum NavigationAxis: String, CaseIterable {
    case x
    case y
    case z

    /// The letter on the ball of the axis's positive end.
    var letter: String {
        rawValue.uppercased()
    }

    /// The axis in the world.
    var direction: simd_float3 {
        switch self {
        case .x: return simd_float3(1, 0, 0)
        case .y: return simd_float3(0, 1, 0)
        case .z: return simd_float3(0, 0, 1)
        }
    }

    var color: Color {
        switch self {
        case .x: return .editorNavX
        case .y: return .editorNavY
        case .z: return .editorNavZ
        }
    }
}
