//
//  NavigationGizmoGeometry.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics
import simd

/// One end of an axis in the navigation gizmo: a ball with the axis's letter
/// for the positive end, a ring for the negative one.
struct NavigationGizmoHandle: Equatable {
    let axis: NavigationAxis
    let isPositive: Bool
    /// Where the end is from the gizmo's centre, in arms: x to the right and
    /// y up the screen, each from -1 to 1.
    let offset: simd_float2
    /// How far the end comes toward the viewer, from -1 (away) to 1.
    let depth: Float

    /// The view a click on the end goes to: the camera stands on that side
    /// of the pivot and looks back at it.
    var projection: ViewportProjection {
        switch (axis, isPositive) {
        case (.x, true): return .right
        case (.x, false): return .left
        case (.y, true): return .top
        case (.y, false): return .bottom
        case (.z, true): return .front
        case (.z, false): return .back
        }
    }
}

/// Where the navigation gizmo draws the world's axes for a camera, and which
/// end a click lands on. Pure, so it is tested without a view.
enum NavigationGizmoGeometry {
    /// The gizmo's circle.
    static let diameter: CGFloat = 84
    static let ballDiameter: CGFloat = 16
    static let ringDiameter: CGFloat = 14
    /// From the centre of the gizmo to the centre of a ball or a ring that
    /// lies in the plane of the screen.
    static let armLength: CGFloat = 30
    /// How far outside a ball or a ring a click still counts as on it.
    static let hitSlop: CGFloat = 3

    /// The six ends as the camera sees them, the farthest first, so drawing
    /// them in order leaves the nearest on top.
    static func handles(viewSpace: simd_float4x4) -> [NavigationGizmoHandle] {
        var handles: [NavigationGizmoHandle] = []
        for axis in NavigationAxis.allCases {
            let seen = simd_mul(viewSpace, simd_float4(axis.direction, 0))
            let direction = simd_float3(seen.x, seen.y, seen.z)
            let length = simd_length(direction)
            guard length > 0.0001, length.isFinite else {
                continue
            }
            // The camera looks down its negative Z, so its Z comes toward the viewer.
            let unit = direction / length
            handles.append(NavigationGizmoHandle(axis: axis, isPositive: true, offset: simd_float2(unit.x, unit.y), depth: unit.z))
            handles.append(NavigationGizmoHandle(axis: axis, isPositive: false, offset: simd_float2(-unit.x, -unit.y), depth: -unit.z))
        }
        // A stable order for ends at the same depth, so they do not swap places between frames.
        return handles.enumerated()
            .sorted { lhs, rhs in
                lhs.element.depth == rhs.element.depth ? lhs.offset < rhs.offset : lhs.element.depth < rhs.element.depth
            }
            .map(\.element)
    }

    /// The centre of an end in a gizmo of `diameter`, from its top left corner.
    static func center(of handle: NavigationGizmoHandle, diameter: CGFloat = diameter) -> CGPoint {
        let arm = armLength * diameter / Self.diameter
        return CGPoint(
            x: diameter / 2 + CGFloat(handle.offset.x) * arm,
            y: diameter / 2 - CGFloat(handle.offset.y) * arm
        )
    }

    /// The end a click at `point` lands on: the nearest to the viewer of those under it.
    static func handle(at point: CGPoint, in handles: [NavigationGizmoHandle], diameter: CGFloat = diameter) -> NavigationGizmoHandle? {
        let scale = diameter / Self.diameter
        return handles.reversed().first { handle in
            let center = center(of: handle, diameter: diameter)
            let radius = (handle.isPositive ? ballDiameter : ringDiameter) / 2 * scale + hitSlop
            return hypot(point.x - center.x, point.y - center.y) <= radius
        }
    }
}
