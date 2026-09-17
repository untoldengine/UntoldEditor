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

/// Draws the stand-in for entities that exist only as data: a spawn point, a trigger, a rules
/// object. A code component asks for one through `editorRepresentation`; the editor draws it
/// the way it draws its own light markers, in the same pass and with the same billboard
/// pipeline. Nothing here is saved, and the pass is not part of play mode or of a game.
enum EditorRepresentationRenderer {
    struct Marker: Equatable {
        let entityId: EntityID
        let systemImage: String
        let tint: SIMD3<Float>
    }

    /// The entities to mark. One that already shows itself (it has a mesh, or it is a light
    /// with the editor's own marker) is left alone, and so is one being destroyed.
    static func markers() -> [Marker] {
        guard EditorFeatureFlags.enableCodeComponents else { return [] }
        let storageId = getComponentId(for: CodeComponentsComponent.self)
        let transformId = getComponentId(for: LocalTransformComponent.self)
        var result: [Marker] = []
        for entityId in queryEntitiesWithComponentIds([storageId, transformId], in: scene) {
            guard hasComponent(entityId: entityId, componentType: RenderComponent.self) == false,
                  hasComponent(entityId: entityId, componentType: LightComponent.self) == false
            else { continue }
            if let marker = marker(for: entityId) {
                result.append(marker)
            }
        }
        return result
    }

    /// The first component on the entity that asks for a representation decides it.
    static func marker(for entityId: EntityID) -> Marker? {
        for component in CodeComponentSystem.shared.components(on: entityId) {
            if case let .icon(systemImage, tint) = component.editorRepresentation {
                return Marker(entityId: entityId, systemImage: systemImage, tint: tint)
            }
        }
        return nil
    }

    /// Encodes one billboard per marker. The caller has set the light-visual pipeline and its
    /// depth state; this sets the rest, as the light loop before it does.
    static func draw(with renderEncoder: MTLRenderCommandEncoder, viewSpace: inout simd_float4x4) {
        let markers = markers()
        guard markers.isEmpty == false, let indexBuffer = bufferResources.quadIndexBuffer else { return }

        for marker in markers {
            guard let texture = texture(systemImage: marker.systemImage, tint: marker.tint) else { continue }
            var space = worldSpace(of: marker.entityId)

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
    }

    private static func worldSpace(of entityId: EntityID) -> simd_float4x4 {
        if hasComponent(entityId: entityId, componentType: WorldTransformComponent.self),
           let world = scene.get(component: WorldTransformComponent.self, for: entityId)
        {
            return world.space
        }
        return scene.get(component: LocalTransformComponent.self, for: entityId)?.space ?? matrix_identity_float4x4
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
            Logger.logWarning(message: "[Components] No editor icon could be made for the symbol '\(systemImage)'.")
            return nil
        }
        textures[key] = texture
        Logger.log(message: "[Components] Editor icon ready: \(systemImage)", category: "Components")
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

    /// Used when a component names a symbol this macOS does not have.
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
