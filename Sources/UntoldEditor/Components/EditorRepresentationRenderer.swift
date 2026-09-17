//
//  EditorRepresentationRenderer.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import AppKit
import Metal
import simd
import UntoldComponentKit
import UntoldEngine

/// Draws what an entity written in code asks the editor to show besides its geometry: the
/// flag of a spawn point, the control points of a spline. An `EntityPlugin` describes it in
/// `editorRepresentation`; the editor draws it in the pass that draws its own light markers.
/// Nothing here is saved, and the pass is not part of play mode or of a game.
///
/// Icons are hidden by geometry in front of them, like the light markers. Lines and points
/// are drawn over everything, so a handle inside a mesh can still be seen.
enum EditorRepresentationRenderer {
    struct Drawing: Equatable {
        let entityId: EntityID
        let representation: EditorRepresentation
    }

    /// Every entity of a kind written in code that has something to show right now.
    static func drawings() -> [Drawing] {
        guard EditorFeatureFlags.enableCodeComponents else { return [] }
        let storageId = getComponentId(for: ScenePluginsComponent.self)
        let transformId = getComponentId(for: LocalTransformComponent.self)
        var result: [Drawing] = []
        for entityId in queryEntitiesWithComponentIds([storageId, transformId], in: scene).sorted() {
            if let drawing = drawing(for: entityId) {
                result.append(drawing)
            }
        }
        return result
    }

    static func drawing(for entityId: EntityID) -> Drawing? {
        guard let plugin = ScenePluginSystem.shared.entityPlugin(on: entityId) else { return nil }
        let representation = plugin.editorRepresentation
        return representation.isEmpty ? nil : Drawing(entityId: entityId, representation: representation)
    }

    /// The vertices of one polyline as the line pipeline wants them, split so each run fits
    /// the inline vertex data limit. A closed line gets its first point again at the end, and
    /// consecutive runs share a point so the line has no gap.
    static func lineRuns(_ points: [SIMD3<Float>], closed: Bool, maxVerticesPerRun: Int = 250) -> [[SIMD4<Float>]] {
        guard points.count >= 2, maxVerticesPerRun >= 2 else { return [] }
        var vertices = points.map { SIMD4<Float>($0.x, $0.y, $0.z, 1) }
        if closed, let first = vertices.first {
            vertices.append(first)
        }
        var runs: [[SIMD4<Float>]] = []
        var start = 0
        while start < vertices.count - 1 {
            let end = min(start + maxVerticesPerRun, vertices.count)
            runs.append(Array(vertices[start ..< end]))
            start = end - 1
        }
        return runs
    }

    /// Encodes every drawing. The caller has set the light-visual pipeline and its depth
    /// state, which is what the icons need; lines and points set their own.
    static func draw(with renderEncoder: MTLRenderCommandEncoder, viewSpace: inout simd_float4x4) {
        let drawings = drawings()
        guard drawings.isEmpty == false, let indexBuffer = bufferResources.quadIndexBuffer else { return }

        var icons: [(space: simd_float4x4, texture: MTLTexture)] = []
        var lines: [(space: simd_float4x4, runs: [[SIMD4<Float>]])] = []
        var dots: [(center: SIMD3<Float>, texture: MTLTexture)] = []

        for drawing in drawings {
            let space = worldSpace(of: drawing.entityId)
            for item in drawing.representation.items {
                switch item {
                case let .icon(systemImage, tint):
                    if let texture = texture(systemImage: systemImage, tint: tint) {
                        icons.append((space, texture))
                    }
                case let .polyline(points, closed):
                    lines.append((space, lineRuns(points, closed: closed)))
                case let .points(points, tint):
                    guard let texture = dotTexture(tint: tint) else { continue }
                    for point in points {
                        let world = space * SIMD4<Float>(point.x, point.y, point.z, 1)
                        dots.append((SIMD3<Float>(world.x, world.y, world.z), texture))
                    }
                case .handles:
                    let selected = EditorRepresentationHandles.active
                    for placed in EditorRepresentationHandles.placed(in: EditorRepresentation([item]), on: drawing.entityId) {
                        let tint = placed.handle == selected ? SIMD3<Float>(1, 1, 1) : placed.tint
                        guard let texture = dotTexture(tint: tint) else { continue }
                        dots.append((placed.worldPosition, texture))
                    }
                }
            }
        }

        func drawBillboard(space: simd_float4x4, texture: MTLTexture) {
            var space = space
            renderEncoder.setVertexBuffer(bufferResources.quadVerticesBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(bufferResources.quadTexCoordsBuffer, offset: 0, index: 1)
            renderEncoder.setVertexBytes(&viewSpace, length: MemoryLayout<matrix_float4x4>.stride, index: 2)
            renderEncoder.setVertexBytes(&renderInfo.perspectiveSpace, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
            renderEncoder.setVertexBytes(&space, length: MemoryLayout<matrix_float4x4>.stride, index: 4)
            renderEncoder.setFragmentTexture(texture, index: 0)
            renderEncoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: quadIndices.count,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }

        // Icons: the pipeline and depth test the light markers use.
        for icon in icons {
            drawBillboard(space: icon.space, texture: icon.texture)
        }

        // Lines: the pipeline the selection box uses, which ignores depth.
        if lines.isEmpty == false,
           let linePipeline = PipelineManager.shared.renderPipelinesByType[.highlight],
           linePipeline.success, let lineState = linePipeline.pipelineState
        {
            renderEncoder.setRenderPipelineState(lineState)
            renderEncoder.setDepthStencilState(linePipeline.depthState)
            if hasLoggedLines == false {
                hasLoggedLines = true
                Logger.log(message: "[Plugins] Editor lines ready", category: "Plugins")
            }
            var scale = simd_float3(repeating: 1)
            for line in lines {
                var space = line.space
                renderEncoder.setVertexBytes(&viewSpace, length: MemoryLayout<matrix_float4x4>.stride, index: 1)
                renderEncoder.setVertexBytes(&renderInfo.perspectiveSpace, length: MemoryLayout<matrix_float4x4>.stride, index: 2)
                renderEncoder.setVertexBytes(&space, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
                renderEncoder.setVertexBytes(&scale, length: MemoryLayout<simd_float3>.stride, index: 4)
                for run in line.runs {
                    renderEncoder.setVertexBytes(run, length: MemoryLayout<SIMD4<Float>>.stride * run.count, index: 0)
                    renderEncoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: run.count)
                }
            }
        }

        // Points: billboards again, over the lines and over everything else.
        if dots.isEmpty == false,
           let billboardPipeline = PipelineManager.shared.renderPipelinesByType[.lightVisual],
           billboardPipeline.success, let billboardState = billboardPipeline.pipelineState,
           let overlayDepth = overlayDepthState()
        {
            renderEncoder.setRenderPipelineState(billboardState)
            renderEncoder.setDepthStencilState(overlayDepth)
            for dot in dots {
                var space = matrix_identity_float4x4
                space.columns.3 = SIMD4<Float>(dot.center.x, dot.center.y, dot.center.z, 1)
                drawBillboard(space: space, texture: dot.texture)
            }
        }
    }

    private static func worldSpace(of entityId: EntityID) -> simd_float4x4 {
        if hasComponent(entityId: entityId, componentType: WorldTransformComponent.self),
           let world = scene.get(component: WorldTransformComponent.self, for: entityId)
        {
            return world.space
        }
        return scene.get(component: LocalTransformComponent.self, for: entityId)?.space ?? matrix_identity_float4x4
    }

    private static var hasLoggedLines = false
    private static var cachedOverlayDepthState: MTLDepthStencilState?

    /// Passes every fragment and writes no depth: for what must show through geometry.
    private static func overlayDepthState() -> MTLDepthStencilState? {
        if let cachedOverlayDepthState {
            return cachedOverlayDepthState
        }
        guard let device = renderInfo.device else { return nil }
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        cachedOverlayDepthState = device.makeDepthStencilState(descriptor: descriptor)
        return cachedOverlayDepthState
    }

    // MARK: Icon textures

    private struct TextureKey: Hashable {
        let systemImage: String
        let tint: SIMD3<Int>
    }

    static let iconPixelSize = 128
    private static var textures: [TextureKey: MTLTexture] = [:]
    private static var failedKeys: Set<TextureKey> = []

    /// A texture for the symbol, made once per symbol and tint and kept for the session.
    static func texture(systemImage: String, tint: SIMD3<Float>) -> MTLTexture? {
        let quantized = SIMD3<Int>(Int((tint.x * 255).rounded()), Int((tint.y * 255).rounded()), Int((tint.z * 255).rounded()))
        let key = TextureKey(systemImage: systemImage, tint: quantized)
        if let cached = textures[key] {
            return cached
        }
        guard failedKeys.contains(key) == false, let device = renderInfo.device else { return nil }
        guard let pixels = iconPixels(systemImage: systemImage, tint: tint, size: iconPixelSize),
              let texture = makeTexture(pixels: pixels, size: iconPixelSize, device: device)
        else {
            failedKeys.insert(key)
            Logger.logWarning(message: "[Plugins] No editor icon could be made for the symbol '\(systemImage)'.")
            return nil
        }
        textures[key] = texture
        Logger.log(message: "[Plugins] Editor icon ready: \(systemImage)", category: "Plugins")
        return texture
    }

    /// RGBA pixels, top row first: the tinted symbol on a dark disc, so it reads against a
    /// bright scene as well as a dark one. The billboard shader cuts alpha at one half, so
    /// the disc is opaque and everything around it is clear.
    static func iconPixels(systemImage: String, tint: SIMD3<Float>, size: Int) -> [UInt8]? {
        guard size > 0, NSImage(systemSymbolName: systemImage, accessibilityDescription: nil) != nil
            || NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) != nil
        else { return nil }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }

            let bounds = CGRect(x: 0, y: 0, width: size, height: size)
            context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
            context.fillEllipse(in: bounds.insetBy(dx: 2, dy: 2))
            context.setStrokeColor(CGColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1))
            context.setLineWidth(CGFloat(size) / 24)
            context.strokeEllipse(in: bounds.insetBy(dx: CGFloat(size) / 16, dy: CGFloat(size) / 16))

            let color = NSColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1)
            let configuration = NSImage.SymbolConfiguration(pointSize: CGFloat(size) * 0.5, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
            let symbol = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil)
            guard let image = symbol?.withSymbolConfiguration(configuration) else { return false }

            let limit = CGFloat(size) * 0.56
            let scale = min(limit / max(image.size.width, 1), limit / max(image.size.height, 1))
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let target = CGRect(
                x: (CGFloat(size) - drawSize.width) / 2,
                y: (CGFloat(size) - drawSize.height) / 2,
                width: drawSize.width,
                height: drawSize.height
            )
            let graphics = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphics
            image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        return drawn ? pixels : nil
    }

    // MARK: Point textures

    private static var dotTextures: [SIMD3<Int>: MTLTexture] = [:]

    /// A texture for a control point, made once per tint.
    static func dotTexture(tint: SIMD3<Float>) -> MTLTexture? {
        let key = SIMD3<Int>(Int((tint.x * 255).rounded()), Int((tint.y * 255).rounded()), Int((tint.z * 255).rounded()))
        if let cached = dotTextures[key] {
            return cached
        }
        guard let device = renderInfo.device,
              let pixels = dotPixels(tint: tint, size: iconPixelSize),
              let texture = makeTexture(pixels: pixels, size: iconPixelSize, device: device)
        else { return nil }
        dotTextures[key] = texture
        Logger.log(message: "[Plugins] Editor point marker ready", category: "Plugins")
        return texture
    }

    /// RGBA pixels, top row first: a tinted disc with a dark rim, covering less than half of
    /// the billboard so a control point reads as a point, not as a marker.
    static func dotPixels(tint: SIMD3<Float>, size: Int) -> [UInt8]? {
        guard size > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            let radius = CGFloat(size) * 0.22
            let center = CGFloat(size) / 2
            let disc = CGRect(x: center - radius, y: center - radius, width: radius * 2, height: radius * 2)
            context.setFillColor(CGColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1))
            context.fillEllipse(in: disc.insetBy(dx: -CGFloat(size) * 0.04, dy: -CGFloat(size) * 0.04))
            context.setFillColor(CGColor(red: CGFloat(tint.x), green: CGFloat(tint.y), blue: CGFloat(tint.z), alpha: 1))
            context.fillEllipse(in: disc)
            return true
        }
        return drawn ? pixels : nil
    }

    /// Used when an entity names a symbol this macOS does not have.
    static let fallbackSymbol = "questionmark.circle"

    private static func makeTexture(pixels: [UInt8], size: Int, device: MTLDevice) -> MTLTexture? {
        // The pixels are sRGB, as drawn. Sampled as such, the tint a component names is the tint
        // on screen; read as linear values they come out washed.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: size, height: size, mipmapped: false)
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Editor representation icon"
        pixels.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, size, size),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: size * 4
            )
        }
        return texture
    }
}
