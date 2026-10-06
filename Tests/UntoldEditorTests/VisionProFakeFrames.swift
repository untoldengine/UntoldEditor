//
//  VisionProFakeFrames.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import Metal
import simd
@testable import UntoldEditor
@testable import UntoldEngine

/// Frames for the headset's loop without a headset: two eyes drawn into
/// textures of the test's own, from a pose the test gives, a set number of
/// times; or, kept open, frames with nothing to draw until the source is
/// stopped, as a headset that shows nothing yet.
final class VisionProFakeFrames: VisionProFrameSource {
    final class Frame: VisionProFrame {
        let eyes: VisionProFrameEyes?
        private(set) var phases: [String] = []
        private(set) var presentedIn: MTLCommandBuffer?
        /// Whether the camera was held against the keys and the mouse when
        /// the frame was presented, right after its eyes were drawn.
        private(set) var cameraWasHeldAtPresent = false

        init(eyes: VisionProFrameEyes?) {
            self.eyes = eyes
        }

        func beginUpdate() {
            phases.append("beginUpdate")
        }

        func endUpdate() {
            phases.append("endUpdate")
        }

        func waitForDrawingTime() {
            phases.append("wait")
        }

        func beginDrawing() -> Bool {
            phases.append("beginDrawing")
            return true
        }

        func acquireEyes() -> VisionProFrameEyes? {
            phases.append("acquire")
            return eyes
        }

        func present(commandBuffer: MTLCommandBuffer) {
            phases.append("present")
            presentedIn = commandBuffer
            if VisionProPreviewState.shared.cameraLock.try() {
                VisionProPreviewState.shared.cameraLock.unlock()
            } else {
                cameraWasHeldAtPresent = true
            }
        }

        func endDrawing() {
            phases.append("endDrawing")
        }
    }

    /// Half the distance between the eyes, as on a headset.
    static let halfEyeDistance: Float = 0.032

    let colorTextures: [MTLTexture]
    let depthTextures: [MTLTexture]
    private(set) var frames: [Frame] = []
    private var left: Int
    private let keepsOpen: Bool
    private let lock = NSLock()
    private var stopped = false
    private let opened = DispatchSemaphore(value: 0)
    /// Where the headset is, from its origin, for the frames to come.
    var originFromDevice = matrix_identity_float4x4
    /// Open-ended frames carry eyes, as a headset that shows the scene; off,
    /// they carry none, as one that shows nothing yet.
    var showsEyesWhileOpen = false

    /// Textures of `eyeSize` for `count` frames; `count` nil keeps the source
    /// open with empty frames until it is stopped.
    init(device: MTLDevice, eyeSize: (width: Int, height: Int), count: Int?) {
        let color = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm_srgb, width: eyeSize.width, height: eyeSize.height, mipmapped: false
        )
        color.usage = [.renderTarget, .shaderRead]
        color.storageMode = .shared
        let depth = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: eyeSize.width, height: eyeSize.height, mipmapped: false
        )
        depth.usage = [.renderTarget, .shaderRead]
        depth.storageMode = .private
        colorTextures = (0 ..< 2).compactMap { _ in device.makeTexture(descriptor: color) }
        depthTextures = (0 ..< 2).compactMap { _ in device.makeTexture(descriptor: depth) }
        left = count ?? 0
        keepsOpen = count == nil
    }

    private var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func nextFrame() -> VisionProFrame? {
        if keepsOpen {
            // A headset that is on but shows nothing yet: a frame now and then.
            _ = opened.wait(timeout: .now() + .milliseconds(20))
            guard isStopped == false else { return nil }
            let frame = Frame(eyes: showsEyesWhileOpen ? eyes() : nil)
            frames.append(frame)
            return frame
        }
        guard isStopped == false, left > 0 else { return nil }
        left -= 1
        let frame = Frame(eyes: eyes())
        frames.append(frame)
        return frame
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        opened.signal()
    }

    private func eyes() -> VisionProFrameEyes {
        let aspect = Float(colorTextures[0].width) / Float(colorTextures[0].height)
        let projection = matrixPerspectiveRightHandReverseZ(fovyRadians: .pi / 2, aspectRatio: aspect, nearZ: 0.1, farZ: 100)
        let eyes = (0 ..< 2).map { index -> VisionProEye in
            let side = index == 0 ? -Self.halfEyeDistance : Self.halfEyeDistance
            let deviceFromView = matrix4x4Translation(side, 0, 0)
            return VisionProEye(
                colorTexture: colorTextures[index],
                depthTexture: depthTextures[index],
                viewFromOrigin: simd_inverse(simd_mul(originFromDevice, deviceFromView)),
                projection: projection
            )
        }
        return VisionProFrameEyes(originFromDevice: originFromDevice, eyes: eyes)
    }

    /// A pixel of a color texture as red, green, blue, alpha from 0 to 255.
    static func pixel(of texture: MTLTexture, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(&bytes, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        // The texture is BGRA.
        return (bytes[2], bytes[1], bytes[0], bytes[3])
    }
}
