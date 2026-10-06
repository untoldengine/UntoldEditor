//
//  VisionProFrameSource.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Metal
import simd

/// One eye of a frame for the headset: the textures to draw it into, how
/// the eye sees the headset's own space, and its projection.
struct VisionProEye {
    let colorTexture: MTLTexture
    let depthTexture: MTLTexture
    /// From the headset's origin, where its tracking began, into this eye's view.
    let viewFromOrigin: simd_float4x4
    let projection: simd_float4x4
}

/// What a frame hands over to draw: where the headset is, from its origin,
/// and its eyes. No eyes while the headset is not tracked: the frame is then
/// presented with nothing drawn, as the compositor asks.
struct VisionProFrameEyes {
    let originFromDevice: simd_float4x4?
    let eyes: [VisionProEye]
}

/// One frame the headset asked for, through the phases the compositor
/// wants them in: an update, a wait for the right moment, then the drawing.
protocol VisionProFrame: AnyObject {
    func beginUpdate()
    func endUpdate()
    /// Waits until the moment the compositor wants the drawing to begin.
    func waitForDrawingTime()
    /// Begins the drawing; false when the frame is no longer wanted.
    func beginDrawing() -> Bool
    /// The eyes to draw, or nil when the compositor gives none for this
    /// frame: nothing is drawn or presented then, and the drawing is not
    /// ended.
    func acquireEyes() -> VisionProFrameEyes?
    /// Hands the eyes to the headset, encoded after the drawing.
    func present(commandBuffer: MTLCommandBuffer)
    func endDrawing()
}

/// Where the frames come from: the headset through CompositorServices, or
/// a test with textures of its own.
protocol VisionProFrameSource: AnyObject {
    /// The next frame, waiting for the headset to ask for one; nil once the
    /// headset is gone or the source was stopped.
    func nextFrame() -> VisionProFrame?
    /// Ends the source: tracking stops and `nextFrame` returns nil.
    func stop()
}
