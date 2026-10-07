//
//  VisionProMirrorTests.swift
//  UntoldEditorTests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import MetalKit
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The viewport's mirror of the headset's eye: its pipeline names what the
/// viewport's drawable comes with, and the eye lands in the middle of the
/// view at its own proportions. Run with `MTL_DEBUG_LAYER=1` in the
/// environment for Metal's own check of the pipeline against the drawable.
@MainActor
final class VisionProMirrorTests: XCTestCase {
    private var window: NSWindow!
    private var renderer: UntoldRenderer!

    override func setUp() {
        super.setUp()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 32),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        guard let created = UntoldRenderer.create() else {
            XCTFail("Failed to initialize the renderer")
            return
        }
        renderer = created
        window.contentView = created.metalView
    }

    override func tearDown() {
        renderer = nil
        window = nil
        super.tearDown()
    }

    func test_thePipelineNamesTheDepthAndTheStencil_theViewsDrawableComesWith() throws {
        let device = try XCTUnwrap(renderInfo.device)
        let library = try device.makeLibrary(source: VisionProMirror.shaderSource, options: nil)

        let depthOnly = VisionProMirror.pipelineDescriptor(colorFormat: .bgra8Unorm_srgb, depthStencilFormat: .depth32Float, library: library)
        XCTAssertEqual(depthOnly.colorAttachments[0].pixelFormat, .bgra8Unorm_srgb)
        XCTAssertEqual(depthOnly.depthAttachmentPixelFormat, .depth32Float)
        XCTAssertEqual(depthOnly.stencilAttachmentPixelFormat, MTLPixelFormat.invalid)
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: depthOnly))

        let both = VisionProMirror.pipelineDescriptor(colorFormat: .bgra8Unorm, depthStencilFormat: .depth32Float_stencil8, library: library)
        XCTAssertEqual(both.depthAttachmentPixelFormat, .depth32Float_stencil8)
        XCTAssertEqual(both.stencilAttachmentPixelFormat, .depth32Float_stencil8)

        let none = VisionProMirror.pipelineDescriptor(colorFormat: .bgra8Unorm, depthStencilFormat: .invalid, library: library)
        XCTAssertEqual(none.depthAttachmentPixelFormat, MTLPixelFormat.invalid)
        XCTAssertEqual(none.stencilAttachmentPixelFormat, MTLPixelFormat.invalid)
    }

    func test_theMirrorDrawsTheEye_intoAPassWithADepthAttachment_asTheViewportsDrawableIs() throws {
        let view = renderer.metalView
        XCTAssertEqual(view.depthStencilPixelFormat, .depth32Float, "the viewport's drawable comes with a depth attachment")
        let device = try XCTUnwrap(renderInfo.device)
        let mirror = VisionProMirror(device: device)

        // A square red eye in a wide pass: the eye takes the middle, the
        // sides show the background.
        let eye = try XCTUnwrap(Self.makeRedEye(device: device, size: 16))
        let copy = try XCTUnwrap(renderInfo.commandQueue.makeCommandBuffer())
        mirror.copy(eye: eye, commandBuffer: copy)
        copy.commit()
        copy.waitUntilCompleted()
        let deadline = Date().addingTimeInterval(2)
        while mirror.latestEye == nil, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNotNil(mirror.latestEye)

        let (color, depth) = try Self.makePass(device: device, width: 64, height: 32, colorFormat: view.colorPixelFormat, depthFormat: view.depthStencilPixelFormat)
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = color
        descriptor.depthAttachment.texture = depth
        let commandBuffer = try XCTUnwrap(renderInfo.commandQueue.makeCommandBuffer())
        mirror.encode(
            into: descriptor, size: CGSize(width: 64, height: 32),
            colorFormat: view.colorPixelFormat, depthStencilFormat: view.depthStencilPixelFormat,
            commandBuffer: commandBuffer
        )
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertNil(commandBuffer.error)

        let middle = VisionProFakeFrames.pixel(of: color, x: 32, y: 16)
        let side = VisionProFakeFrames.pixel(of: color, x: 2, y: 16)
        XCTAssertGreaterThan(Int(middle.r), 200, "the eye, red, in the middle")
        XCTAssertLessThan(Int(middle.g), 60)
        XCTAssertLessThan(Int(side.r), 120, "the background at the side")
        XCTAssertLessThan(abs(Int(side.r) - Int(side.g)), 20, "the background is a grey")
    }

    private static func makePass(device: MTLDevice, width: Int, height: Int, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) throws -> (MTLTexture, MTLTexture) {
        let color = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: colorFormat, width: width, height: height, mipmapped: false)
        color.usage = [.renderTarget, .shaderRead]
        color.storageMode = .shared
        let depth = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: depthFormat, width: width, height: height, mipmapped: false)
        depth.usage = [.renderTarget]
        depth.storageMode = .private
        return try (XCTUnwrap(device.makeTexture(descriptor: color)), XCTUnwrap(device.makeTexture(descriptor: depth)))
    }

    private static func makeRedEye(device: MTLDevice, size: Int) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: size, height: size, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        // BGRA.
        let bytes = [UInt8](repeating: 0, count: size * size * 4).enumerated().map { index, _ -> UInt8 in
            index % 4 == 2 || index % 4 == 3 ? 255 : 0
        }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        return texture
    }
}
