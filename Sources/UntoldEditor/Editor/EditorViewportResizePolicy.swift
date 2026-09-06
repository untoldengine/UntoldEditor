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
import UntoldEngine

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
///
/// Growing the viewport would still expose a band where nothing was rendered.
/// A resize hold (`beginResizeHold(of:)`) avoids that by rendering the frozen
/// frame at the screen's size first, with the field of view widened so the
/// visible crop is unchanged, and keeping the Metal view at that size inside
/// its clipping host until the resize ends.
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

    // MARK: - Resize hold

    /// Field of view, in degrees, that makes the central `visibleHeight` points
    /// of a render `overscanHeight` points tall match a render of the visible
    /// size at `fov`. The engine ties its vertical field of view to the
    /// drawable height, so widening it by the height ratio keeps the crop the
    /// same.
    static func overscanFieldOfView(fov: Float, visibleHeight: CGFloat, overscanHeight: CGFloat) -> Float {
        guard visibleHeight > 0, overscanHeight > visibleHeight else { return fov }
        let halfTangent = tan(fov * .pi / 360) * Float(overscanHeight / visibleHeight)
        return atan(halfTangent) * 360 / .pi
    }

    /// The size to render the frozen frame at: the visible size grown to the
    /// screen the window is on, so no resize within that screen outgrows it.
    static func overscanSize(visible: CGSize, screen: CGSize?) -> CGSize {
        guard let screen else { return visible }
        return CGSize(width: max(visible.width, screen.width), height: max(visible.height, screen.height))
    }

    private nonisolated(unsafe) static var heldFieldOfView: Float?

    /// Freezes the viewport for a resize and pauses the render loop.
    ///
    /// When the Metal view sits in an `EditorViewportHostView`, one frame is
    /// first rendered at the screen's size with the field of view widened to
    /// keep the visible crop unchanged, and the view is held at that size,
    /// centred, until `endResizeHold(of:)`. Growing the viewport then reveals
    /// scene that was already rendered.
    static func beginResizeHold(of view: MTKView) {
        // Pause first: MTKView only draws synchronously from `draw()` while it
        // is paused (explicit drawing mode); while the display link drives it
        // the call is ignored.
        view.isPaused = true
        guard let host = view.superview as? EditorViewportHostView, host.heldMetalViewSize == nil else { return }
        let visible = host.bounds.size
        let overscan = overscanSize(visible: visible, screen: view.window?.screen?.frame.size)
        guard visible.height > 0, overscan != visible else { return }

        let original = fov
        heldFieldOfView = original
        // Set before the resize: the engine rebuilds its projection from `fov`
        // when the drawable size changes.
        fov = overscanFieldOfView(fov: original, visibleHeight: visible.height, overscanHeight: overscan.height)
        host.heldMetalViewSize = overscan

        // Present the overscan frame in the same transaction as the size
        // change, so the band never shows, and let the GPU finish it before
        // that transaction commits.
        (view.layer as? CAMetalLayer)?.presentsWithTransaction = true
        view.draw()
        let queue: MTLCommandQueue? = renderInfo.commandQueue
        if let sync = queue?.makeCommandBuffer() {
            sync.commit()
            sync.waitUntilCompleted()
        }
    }

    /// Ends a hold started by `beginResizeHold(of:)`: restores the field of
    /// view, lets the Metal view fill its host again (the engine rebuilds the
    /// projection for the final size) and resumes the render loop.
    static func endResizeHold(of view: MTKView) {
        if let host = view.superview as? EditorViewportHostView, host.heldMetalViewSize != nil {
            if let original = heldFieldOfView {
                fov = original
                heldFieldOfView = nil
            }
            (view.layer as? CAMetalLayer)?.presentsWithTransaction = false
            host.heldMetalViewSize = nil
        }
        view.isPaused = false
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
