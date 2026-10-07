//
//  VisionProMirror.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Metal
import MetalKit
import simd
import UntoldEngine

/// What the Mac's viewport shows while the headset shows the scene: the
/// left eye, copied after each of the headset's frames and drawn into the
/// viewport with its own proportions kept. The viewport's Metal view draws
/// through it meanwhile, instead of through the engine, which the headset's
/// loop drives then.
final class VisionProMirror: NSObject, MTKViewDelegate {
    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct MirrorVertexOut {
        float4 position [[position]];
        float2 uv;
    };

    // One triangle over the whole view; the eye lies in the middle of it at
    // its own proportions, `fit` being the part of the view it takes each way.
    vertex MirrorVertexOut visionProMirrorVertex(uint id [[vertex_id]], constant float2 &fit [[buffer(0)]]) {
        float2 corner = float2((id << 1) & 2, id & 2);
        MirrorVertexOut out;
        out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
        float2 uv = float2(corner.x, 1.0 - corner.y);
        out.uv = (uv - 0.5) / fit + 0.5;
        return out;
    }

    fragment float4 visionProMirrorFragment(
        MirrorVertexOut in [[stage_in]],
        texture2d<float> eye [[texture(0)]],
        constant float4 &background [[buffer(0)]])
    {
        if (any(in.uv < 0.0) || any(in.uv > 1.0)) {
            return background;
        }
        constexpr sampler linearSampler(filter::linear, address::clamp_to_edge);
        return float4(eye.sample(linearSampler, in.uv).rgb, 1.0);
    }
    """

    private let device: MTLDevice
    private let lock = NSLock()
    /// Run on the main thread before each of the viewport's frames, as the
    /// engine's own draw would run the editor's per-frame input: the session
    /// puts the key-up check there.
    var onFrame: (() -> Void)?
    /// Two copies, written in turn, so the one on screen is never the one
    /// being written.
    private var copies: [MTLTexture] = []
    private var nextCopy = 0
    private var latest: MTLTexture?
    private var pipeline: MTLRenderPipelineState?
    private var pipelineFormats: (color: MTLPixelFormat, depthStencil: MTLPixelFormat)?

    init(device: MTLDevice) {
        self.device = device
    }

    /// The eye the viewport shows, once the GPU has copied it.
    var latestEye: MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    /// Copies the eye in the headset's own command buffer; the viewport shows
    /// the copy once that buffer is done.
    func copy(eye: MTLTexture, commandBuffer: MTLCommandBuffer) {
        guard let target = copyTexture(matching: eye), let blit = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        blit.label = "Vision Pro Mirror Copy"
        blit.copy(from: eye, to: target)
        blit.endEncoding()
        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            lock.lock()
            latest = target
            lock.unlock()
        }
    }

    private func copyTexture(matching eye: MTLTexture) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        if copies.count != 2 || copies[0].width != eye.width || copies[0].height != eye.height || copies[0].pixelFormat != eye.pixelFormat {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: eye.pixelFormat, width: eye.width, height: eye.height, mipmapped: false
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .private
            copies = (0 ..< 2).compactMap { index in
                let texture = device.makeTexture(descriptor: descriptor)
                texture?.label = "Vision Pro Mirror \(index)"
                return texture
            }
            latest = nil
            nextCopy = 0
        }
        guard copies.count == 2 else {
            return nil
        }
        let target = copies[nextCopy]
        nextCopy = (nextCopy + 1) % 2
        return target
    }

    /// How much of the view the eye takes each way, keeping its proportions.
    static func fit(eye: CGSize, in view: CGSize) -> simd_float2 {
        guard eye.width > 0, eye.height > 0, view.width > 0, view.height > 0 else {
            return simd_float2(1, 1)
        }
        let eyeAspect = eye.width / eye.height
        let viewAspect = view.width / view.height
        if eyeAspect > viewAspect {
            return simd_float2(1, Float(viewAspect / eyeAspect))
        }
        return simd_float2(Float(eyeAspect / viewAspect), 1)
    }

    // MARK: - MTKViewDelegate

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        onFrame?()
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = renderInfo.commandQueue.makeCommandBuffer()
        else {
            return
        }
        commandBuffer.label = "Vision Pro Mirror"
        encode(
            into: descriptor, size: view.drawableSize,
            colorFormat: view.colorPixelFormat, depthStencilFormat: view.depthStencilPixelFormat,
            commandBuffer: commandBuffer
        )
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Draws the latest eye over the background, or the background alone,
    /// into the pass described: the view's drawable, or a test's textures.
    func encode(
        into descriptor: MTLRenderPassDescriptor, size: CGSize,
        colorFormat: MTLPixelFormat, depthStencilFormat: MTLPixelFormat,
        commandBuffer: MTLCommandBuffer
    ) {
        let background = EditorViewportResizePolicy.exposedBackgroundColor
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.x), green: Double(background.y), blue: Double(background.z), alpha: 1
        )
        // The mirror writes no depth and no stencil.
        descriptor.depthAttachment.loadAction = .dontCare
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.stencilAttachment.loadAction = .dontCare
        descriptor.stencilAttachment.storeAction = .dontCare
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }
        if let eye = latestEye,
           let pipeline = makePipelineIfNeeded(colorFormat: colorFormat, depthStencilFormat: depthStencilFormat)
        {
            var fit = Self.fit(eye: CGSize(width: eye.width, height: eye.height), in: size)
            var backgroundColor = background
            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&fit, length: MemoryLayout<simd_float2>.stride, index: 0)
            encoder.setFragmentBytes(&backgroundColor, length: MemoryLayout<simd_float4>.stride, index: 0)
            encoder.setFragmentTexture(eye, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
    }

    private func makePipelineIfNeeded(colorFormat: MTLPixelFormat, depthStencilFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        if let pipeline, let formats = pipelineFormats, formats.color == colorFormat, formats.depthStencil == depthStencilFormat {
            return pipeline
        }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            let descriptor = Self.pipelineDescriptor(colorFormat: colorFormat, depthStencilFormat: depthStencilFormat, library: library)
            let made = try device.makeRenderPipelineState(descriptor: descriptor)
            pipeline = made
            pipelineFormats = (colorFormat, depthStencilFormat)
            return made
        } catch {
            Logger.log(message: "Vision Pro preview: the viewport cannot show the headset's eye (\(error.localizedDescription)).")
            return nil
        }
    }

    /// The pipeline for a view's formats: its colour, and the depth and the
    /// stencil its drawable comes with, which a pipeline has to name even
    /// though the mirror writes neither.
    static func pipelineDescriptor(colorFormat: MTLPixelFormat, depthStencilFormat: MTLPixelFormat, library: MTLLibrary) -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Vision Pro Mirror Pipeline"
        descriptor.vertexFunction = library.makeFunction(name: "visionProMirrorVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "visionProMirrorFragment")
        descriptor.colorAttachments[0].pixelFormat = colorFormat
        if [.depth16Unorm, .depth32Float, .depth24Unorm_stencil8, .depth32Float_stencil8].contains(depthStencilFormat) {
            descriptor.depthAttachmentPixelFormat = depthStencilFormat
        }
        if [.stencil8, .depth24Unorm_stencil8, .depth32Float_stencil8, .x32_stencil8, .x24_stencil8].contains(depthStencilFormat) {
            descriptor.stencilAttachmentPixelFormat = depthStencilFormat
        }
        return descriptor
    }
}
