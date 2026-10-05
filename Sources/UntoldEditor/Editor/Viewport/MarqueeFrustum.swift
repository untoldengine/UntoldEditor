//
//  MarqueeFrustum.swift
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

extension MarqueeGeometry {
    /// The part of the world that can show in the rectangle: what lies
    /// between the four planes that go through the camera and the sides of
    /// the rectangle, in front of the camera.
    ///
    /// It is made once for a rectangle and then asked about every entity of
    /// the scene, so asking is kept cheap: a box that is all beyond one of
    /// the planes, as nearly every box of a large scene is, is told outside
    /// from its middle and its size alone.
    struct Frustum {
        let area: DeviceRect

        /// From the world to clip space: the camera's projection after its view.
        let toClip: simd_float4x4

        /// The planes, each as the row of numbers that tells how far a point
        /// of the world is on the rectangle's side of it: the left, the
        /// right, the bottom and the top of the rectangle, and the plane the
        /// camera stands on.
        let sides: [simd_float4]

        /// Nil for a viewport without a size, where nothing shows.
        init?(_ rect: CGRect, view: View) {
            guard let area = MarqueeGeometry.deviceRect(rect, in: view.size) else {
                return nil
            }
            self.area = area
            toClip = simd_mul(view.perspectiveSpace, view.viewSpace)

            // A row of the matrix gives one clip coordinate of a point of
            // the world, so a side of the rectangle, such as x >= low * w,
            // is a row of numbers as well.
            let rows = toClip.transpose
            let x = rows.columns.0
            let y = rows.columns.1
            let w = rows.columns.3
            sides = [
                x - area.low.x * w,
                area.high.x * w - x,
                y - area.low.y * w,
                area.high.y * w - y,
                w,
            ]
        }

        /// How a box given in an entity's own space, which `modelSpace`
        /// carries into the world, stands to the rectangle.
        ///
        /// It is outside when all of it is beyond the same plane: nothing
        /// drawn within the box can then fall on the rectangle. That errs on
        /// the side of `across`: a box near a corner of the rectangle may be
        /// told across though it shows nowhere in it. It is inside with all
        /// eight of its corners in front of the camera and within the
        /// rectangle, its border included.
        func place(
            ofBoxMinimum minimum: simd_float3,
            boxMaximum maximum: simd_float3,
            modelSpace: simd_float4x4
        ) -> Place {
            let middle = simd_float4((minimum + maximum) * 0.5, 1)
            let half = simd_abs(maximum - minimum) * 0.5

            // All of it is beyond a plane when its middle is farther beyond
            // than the box reaches back toward it. The planes go through the
            // camera, so this holds for a box behind the camera as well.
            for side in sides {
                let sideForTheBox = simd_mul(side, modelSpace)
                let reach = simd_dot(simd_abs(simd_float3(sideForTheBox.x, sideForTheBox.y, sideForTheBox.z)), half)
                if simd_dot(sideForTheBox, middle) + reach < 0 {
                    return .outside
                }
            }

            let boxToClip = simd_mul(toClip, modelSpace)
            for corner in 0 ..< 8 {
                let clip = simd_mul(boxToClip, simd_float4(
                    corner & 1 == 0 ? minimum.x : maximum.x,
                    corner & 2 == 0 ? minimum.y : maximum.y,
                    corner & 4 == 0 ? minimum.z : maximum.z,
                    1
                ))
                // A corner behind the camera has no place on the screen, and
                // neither has one that is nowhere.
                guard area.contains(clip) else {
                    return .across
                }
            }
            return .inside
        }

        /// Whether a point of the world shows in the rectangle: for what has
        /// a place and no box, such as a light.
        func contains(_ point: simd_float3) -> Bool {
            area.contains(simd_mul(toClip, simd_float4(point, 1)))
        }
    }
}
