//
//  MarqueeGeometry.swift
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

/// The rectangle dragged over the viewport and what stands inside it. Pure,
/// so it is tested without a view or a scene.
///
/// The rectangle is measured as the canvas measures the pointer: in points
/// from the bottom left of the viewport. An entity is inside when all of its
/// box is, the one drawn around it when it is selected: every corner of the
/// box in front of the camera and within the rectangle. A floor or a wall
/// that reaches out of the rectangle is therefore left out, however much of
/// it shows in it.
enum MarqueeGeometry {
    /// The nearest a point may be to the camera's plane and still be projected.
    static let nearestDepth: Float = 0.01

    /// How the camera sees the world: its two matrices and the size of the
    /// viewport in points.
    struct View {
        let viewSpace: simd_float4x4
        let perspectiveSpace: simd_float4x4
        let size: CGSize
    }

    /// The rectangle between where a drag began and where it is now,
    /// whichever way it went.
    static func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    /// The same rectangle for a view that measures from its top left, as
    /// SwiftUI does.
    static func flipped(_ rect: CGRect, inHeight height: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Whether a box given in an entity's own space, which `modelSpace`
    /// carries into the world, stands inside the rectangle: all eight of its
    /// corners in front of the camera and within the rectangle, its border
    /// included. A corner behind the camera has no place on the screen, so a
    /// box that reaches there is not inside.
    static func contains(
        _ rect: CGRect,
        boxMinimum minimum: simd_float3,
        boxMaximum maximum: simd_float3,
        modelSpace: simd_float4x4,
        view: View
    ) -> Bool {
        guard let area = deviceRect(rect, in: view.size) else {
            return false
        }

        let toClip = simd_mul(simd_mul(view.perspectiveSpace, view.viewSpace), modelSpace)
        for corner in 0 ..< 8 {
            let clip = simd_mul(toClip, simd_float4(
                corner & 1 == 0 ? minimum.x : maximum.x,
                corner & 2 == 0 ? minimum.y : maximum.y,
                corner & 4 == 0 ? minimum.z : maximum.z,
                1
            ))
            guard area.contains(clip) else {
                return false
            }
        }
        return true
    }

    /// Whether a point of the world is inside the rectangle: for what has a
    /// place and no box, such as a light.
    static func contains(_ rect: CGRect, point: simd_float3, view: View) -> Bool {
        guard let area = deviceRect(rect, in: view.size) else {
            return false
        }
        return area.contains(simd_mul(simd_mul(view.perspectiveSpace, view.viewSpace), simd_float4(point, 1)))
    }

    // MARK: - The parts

    /// A rectangle in device coordinates, which run from -1 to 1 across the
    /// viewport with Y up.
    struct DeviceRect: Equatable {
        let low: simd_float2
        let high: simd_float2

        /// Whether a point in clip space is in front of the camera and, on
        /// the screen, within the rectangle or on its border.
        func contains(_ clip: simd_float4) -> Bool {
            guard clip.w.isFinite, clip.w >= MarqueeGeometry.nearestDepth, clip.x.isFinite, clip.y.isFinite else {
                return false
            }
            let place = simd_float2(clip.x, clip.y) / clip.w
            return place.x >= low.x && place.x <= high.x && place.y >= low.y && place.y <= high.y
        }
    }

    static func deviceRect(_ rect: CGRect, in size: CGSize) -> DeviceRect? {
        guard size.width > 0, size.height > 0, rect.isNull == false, rect.isInfinite == false else {
            return nil
        }
        let low = simd_float2(
            Float(rect.minX / size.width) * 2 - 1,
            Float(rect.minY / size.height) * 2 - 1
        )
        let high = simd_float2(
            Float(rect.maxX / size.width) * 2 - 1,
            Float(rect.maxY / size.height) * 2 - 1
        )
        guard low.x.isFinite, low.y.isFinite, high.x.isFinite, high.y.isFinite else {
            return nil
        }
        return DeviceRect(low: low, high: high)
    }
}
