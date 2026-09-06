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
/// shrinking it trims the edges, with the view clipping the part of the frame
/// that no longer fits. The camera projection is symmetric about the
/// centre, so that is where the content lands once a frame is rendered at the
/// new size, and the scene does not jump when rendering resumes.
///
/// Core Animation sizes the anchored frame as drawable pixels divided by the
/// layer's `contentsScale`, so the two must agree for the frame to fill the
/// view. MTKView and AppKit do not keep them in step (see
/// `syncContentsScale(of:)`), so the scale is re-synced before every frame.
enum EditorViewportResizePolicy {
    /// Colour shown where the viewport extends past the last frame, linear RGB.
    /// Mirrors the engine's main-pass clear colour (`mtkBackgroundColor`), which
    /// the engine does not expose.
    static let exposedBackgroundColor = simd_float4(40.0 / 255.0, 40.0 / 255.0, 45.0 / 255.0, 1.0)

    /// Applies the policy to the layer backing `view`. Idempotent; the settings
    /// persist, so calling it once after the renderer is created is enough.
    /// Pair it with `syncContentsScale(of:)` before each frame.
    static func apply(to view: MTKView) {
        guard let layer = view.layer else { return }
        layer.contentsGravity = .center
        layer.backgroundColor = exposedBackgroundCGColor()
        // When the viewport shrinks, the anchored frame is larger than the
        // layer. AppKit stopped clipping a view's layer to its bounds by
        // default in macOS 14, so without this the excess draws over the
        // neighbouring panels.
        view.clipsToBounds = true
        layer.masksToBounds = true
        syncContentsScale(of: view)
    }

    /// Makes the layer's `contentsScale` equal to the drawable's pixels per
    /// point, so a centre-anchored frame is shown at exactly the view's size.
    /// Returns the scale applied, or nil when the view has no size yet.
    ///
    /// MTKView sizes its drawable from the window's backing scale, but the
    /// layer keeps the scale it was given when the view was created, which is
    /// the main screen's. A window on a 1x external display beside a 2x
    /// built-in one therefore ends up with a 1x drawable under a 2x layer.
    /// `.resize` gravity hides that; `.center` would show the frame at half
    /// size. Call this before every frame so the two never drift apart, for
    /// example after the window moves to another display.
    @discardableResult
    static func syncContentsScale(of view: MTKView) -> CGFloat? {
        guard let layer = view.layer,
              view.bounds.width > 0,
              view.drawableSize.width > 0
        else { return nil }
        let scale = view.drawableSize.width / view.bounds.width
        if abs(layer.contentsScale - scale) > 0.001 {
            layer.contentsScale = scale
        }
        return scale
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
