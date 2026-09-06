//
//  EditorViewportResizePolicy.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import MetalKit
import QuartzCore
import simd

/// Controls how the viewport shows its last rendered frame while its size
/// changes without a new frame being drawn.
///
/// The editor pauses the render loop during live window resizes and panel
/// show/hide animations (see `EditorView`). Core Animation keeps presenting the
/// last drawable in the meantime and, with the default `contentsGravity` of
/// `.resize`, scales it to the new bounds, so the scene looks stretched until
/// rendering resumes and a frame with the right proportions replaces it.
///
/// Anchoring the frame to the centre keeps it at its rendered scale instead:
/// growing the viewport exposes a band of background colour at the edges and
/// shrinking it trims the edges. The camera projection is symmetric about the
/// centre, so that is where the content lands once a frame is rendered at the
/// new size, and the scene does not jump when rendering resumes.
///
/// MTKView keeps `drawableSize == bounds * contentsScale` once the view is in a
/// window, so the anchored frame is displayed at exactly the size it was
/// rendered at and the setting can stay on for the life of the view.
enum EditorViewportResizePolicy {
    /// Colour shown where the viewport extends past the last frame, linear RGB.
    /// Mirrors the engine's main-pass clear colour (`mtkBackgroundColor`), which
    /// the engine does not expose.
    static let exposedBackgroundColor = simd_float4(40.0 / 255.0, 40.0 / 255.0, 45.0 / 255.0, 1.0)

    /// Applies the policy to the layer backing `view`. Idempotent; the settings
    /// persist, so calling it once after the renderer is created is enough.
    static func apply(to view: MTKView) {
        guard let layer = view.layer else { return }
        layer.contentsGravity = .center
        layer.backgroundColor = exposedBackgroundCGColor()
    }

    /// The exposed background as a `CGColor` in the linear sRGB space, matching
    /// how the engine interprets its clear colour.
    static func exposedBackgroundCGColor() -> CGColor? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.linearSRGB) else { return nil }
        let c = exposedBackgroundColor
        let components: [CGFloat] = [CGFloat(c.x), CGFloat(c.y), CGFloat(c.z), CGFloat(c.w)]
        return CGColor(colorSpace: colorSpace, components: components)
    }
}
