//
//  SelectionVisibilityPass.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CShaderTypes
import MetalKit
import simd
import UntoldEngine

/// Tells which entities show in a rectangle of the viewport.
///
/// Every mesh the scene draws that may show in the rectangle is drawn once
/// more, into a texture the size of the rectangle: each with the number of
/// its entity, the nearer over the farther. The numbers left in the texture
/// are then gathered, on the GPU too, so an entity behind a wall or under a
/// floor is not among them. It runs once, when the rectangle is released, on
/// the editor's own pipelines: the engine's passes are not touched.
enum SelectionVisibilityPass {
    /// What the shader takes for each mesh: where to draw it and the number
    /// to draw it with.
    struct Uniforms {
        var modelViewProjection: simd_float4x4
        var identifier: UInt32
    }

    /// The most pixels the texture may have. A larger rectangle is drawn at
    /// a coarser scale.
    static let maximumPixels: CGFloat = 4_000_000

    /// The depth is written as the distance from the camera over this, so
    /// it does not depend on how the engine's projection keeps depth.
    static let farthestDistance: Float = 1_000_000

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct SelectionVisibilityUniforms {
        float4x4 modelViewProjection;
        uint identifier;
    };

    struct SelectionVisibilityVertexIn {
        float3 position [[attribute(0)]];
    };

    struct SelectionVisibilityVertexOut {
        float4 position [[position]];
        float distance;
    };

    struct SelectionVisibilityFragmentOut {
        uint identifier [[color(0)]];
        float depth [[depth(any)]];
    };

    vertex SelectionVisibilityVertexOut selectionVisibilityVertex(
        SelectionVisibilityVertexIn in [[stage_in]],
        constant SelectionVisibilityUniforms &uniforms [[buffer(1)]])
    {
        SelectionVisibilityVertexOut out;
        out.position = uniforms.modelViewProjection * float4(in.position, 1.0);
        out.distance = out.position.w;
        return out;
    }

    fragment SelectionVisibilityFragmentOut selectionVisibilityFragment(
        SelectionVisibilityVertexOut in [[stage_in]],
        constant SelectionVisibilityUniforms &uniforms [[buffer(1)]])
    {
        SelectionVisibilityFragmentOut out;
        out.identifier = uniforms.identifier;
        out.depth = saturate(in.distance / \(farthestDistance));
        return out;
    }

    // Marks every number that is in the texture. Many pixels mark the same
    // one at once, and all of them write the same value.
    kernel void selectionVisibilityGather(
        texture2d<uint, access::read> identifiers [[texture(0)]],
        device atomic_uint *seen [[buffer(0)]],
        uint2 pixel [[thread_position_in_grid]])
    {
        if (pixel.x >= identifiers.get_width() || pixel.y >= identifiers.get_height()) {
            return;
        }
        uint identifier = identifiers.read(pixel).r;
        if (identifier != 0) {
            atomic_store_explicit(&seen[identifier], 1, memory_order_relaxed);
        }
    }
    """

    private struct Pipeline {
        let state: MTLRenderPipelineState
        let depth: MTLDepthStencilState
        let gather: MTLComputePipelineState
    }

    private static var pipeline: Pipeline?
    private static var pipelineCouldNotBeMade = false

    /// The entities among `drawn` that show in `rect`, or nil when that
    /// cannot be told: without a device, or when the pipeline cannot be made.
    ///
    /// - Parameters:
    ///   - rect: the rectangle in points from the bottom left of the viewport.
    ///   - view: how the camera sees the world, and the viewport's size in points.
    ///   - scale: pixels per point of the viewport.
    ///   - drawn: the entities whose meshes may show in the rectangle; those not selectable hide what is behind them all the same.
    static func entitiesSeen(
        in rect: CGRect,
        view: MarqueeGeometry.View,
        scale: CGFloat,
        drawn: [EntityID]
    ) -> Set<EntityID>? {
        guard drawn.isEmpty == false else {
            return []
        }
        guard let device = renderInfo.device,
              let commandQueue = renderInfo.commandQueue,
              let pipeline = makePipelineIfNeeded(device: device),
              let region = PixelRegion(rect: rect, viewSize: view.size, scale: scale)
        else {
            return nil
        }

        let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Uint, width: region.width, height: region.height, mipmapped: false
        )
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: region.width, height: region.height, mipmapped: false
        )
        depthDescriptor.usage = [.renderTarget]
        depthDescriptor.storageMode = .private

        // One mark for each entity drawn, and one for no entity; a new buffer is all zeros.
        guard let color = device.makeTexture(descriptor: colorDescriptor),
              let depth = device.makeTexture(descriptor: depthDescriptor),
              let seen = device.makeBuffer(length: (drawn.count + 1) * MemoryLayout<UInt32>.stride, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return nil
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = color
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        pass.depthAttachment.texture = depth
        pass.depthAttachment.loadAction = .clear
        pass.depthAttachment.storeAction = .dontCare
        pass.depthAttachment.clearDepth = 1

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return nil
        }
        encoder.label = "Selection Visibility Pass"
        encoder.setRenderPipelineState(pipeline.state)
        encoder.setDepthStencilState(pipeline.depth)
        // Both faces of a triangle are drawn, as the engine draws its models.
        encoder.setCullMode(.none)
        // The whole viewport, placed so that the rectangle falls on the texture.
        encoder.setViewport(MTLViewport(
            originX: -Double(region.x),
            originY: -Double(region.y),
            width: Double(region.viewWidth),
            height: Double(region.viewHeight),
            znear: 0,
            zfar: 1
        ))

        let viewProjection = simd_mul(view.perspectiveSpace, view.viewSpace)
        let skipsTransparents = isIgnoringRayIntersectionWithTransparents()
        let positions = Int(modelPassVerticesIndex.rawValue)

        for (index, entityId) in drawn.enumerated() {
            guard let render = scene.get(component: RenderComponent.self, for: entityId),
                  let world = scene.get(component: WorldTransformComponent.self, for: entityId)?.space
            else {
                continue
            }
            for mesh in render.mesh where hasThePositionsThePipelineReads(mesh) {
                var uniforms = Uniforms(
                    modelViewProjection: simd_mul(viewProjection, simd_mul(world, mesh.localSpace)),
                    identifier: UInt32(index + 1)
                )
                encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
                let vertices = mesh.metalKitMesh.vertexBuffers[positions]
                encoder.setVertexBuffer(vertices.buffer, offset: vertices.offset, index: 0)

                for subMesh in mesh.submeshes {
                    // What a click passes through, the rectangle sees through.
                    if skipsTransparents, subMesh.material?.hasTransparency == true {
                        continue
                    }
                    let part = subMesh.metalKitSubmesh
                    encoder.drawIndexedPrimitives(
                        type: part.primitiveType,
                        indexCount: part.indexCount,
                        indexType: part.indexType,
                        indexBuffer: part.indexBuffer.buffer,
                        indexBufferOffset: part.indexBuffer.offset
                    )
                }
            }
        }
        encoder.endEncoding()

        // The numbers in the texture are gathered where they are: reading
        // millions of pixels back to count them here would take far longer.
        guard let gather = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }
        gather.label = "Selection Visibility Gather"
        gather.setComputePipelineState(pipeline.gather)
        gather.setTexture(color, index: 0)
        gather.setBuffer(seen, offset: 0, index: 0)
        let across = pipeline.gather.threadExecutionWidth
        let down = max(1, pipeline.gather.maxTotalThreadsPerThreadgroup / across)
        gather.dispatchThreads(
            MTLSize(width: region.width, height: region.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: across, height: down, depth: 1)
        )
        gather.endEncoding()
        // The answer is waited for, on the mouse-up that asks for it. The
        // wait stays short because only what may show in the rectangle was
        // drawn, into no more than `maximumPixels`.
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.error == nil else {
            return nil
        }

        let marks = seen.contents().bindMemory(to: UInt32.self, capacity: drawn.count + 1)
        return Set(drawn.enumerated().compactMap { marks[$0.offset + 1] != 0 ? $0.element : nil })
    }

    /// Whether a mesh keeps its positions as the pipeline reads them: four
    /// floats to a vertex in a buffer of their own, as the engine's models do.
    static func hasThePositionsThePipelineReads(_ mesh: Mesh) -> Bool {
        let positions = Int(modelPassVerticesIndex.rawValue)
        guard mesh.metalKitMesh.vertexBuffers.count > positions,
              let layout = mesh.metalKitMesh.vertexDescriptor.layouts[positions] as? MDLVertexBufferLayout
        else {
            return false
        }
        return layout.stride == MemoryLayout<simd_float4>.stride
    }

    private static func makePipelineIfNeeded(device: MTLDevice) -> Pipeline? {
        if let pipeline {
            return pipeline
        }
        guard pipelineCouldNotBeMade == false else {
            return nil
        }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "Selection Visibility Pipeline"
            descriptor.vertexFunction = library.makeFunction(name: "selectionVisibilityVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "selectionVisibilityFragment")
            descriptor.colorAttachments[0].pixelFormat = .r32Uint
            descriptor.depthAttachmentPixelFormat = .depth32Float

            // The first three of the four floats the engine keeps for a position.
            let vertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].format = .float3
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
            vertexDescriptor.layouts[0].stepFunction = .perVertex
            descriptor.vertexDescriptor = vertexDescriptor

            let depthDescriptor = MTLDepthStencilDescriptor()
            depthDescriptor.depthCompareFunction = .lessEqual
            depthDescriptor.isDepthWriteEnabled = true

            guard let depth = device.makeDepthStencilState(descriptor: depthDescriptor) else {
                pipelineCouldNotBeMade = true
                return nil
            }
            guard let gatherFunction = library.makeFunction(name: "selectionVisibilityGather") else {
                pipelineCouldNotBeMade = true
                return nil
            }
            let made = try Pipeline(
                state: device.makeRenderPipelineState(descriptor: descriptor),
                depth: depth,
                gather: device.makeComputePipelineState(function: gatherFunction)
            )
            pipeline = made
            return made
        } catch {
            pipelineCouldNotBeMade = true
            Logger.log(message: "The rectangle selects by the entities' boxes: the pass that tells what is seen could not be made (\(error.localizedDescription)).")
            return nil
        }
    }

    /// The pixels of the viewport the rectangle covers, from the viewport's
    /// top left as a texture is laid out, and the viewport's own size in the
    /// same pixels.
    struct PixelRegion: Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
        let viewWidth: Int
        let viewHeight: Int

        /// Nil for a viewport without a size and for a rectangle that is
        /// wholly outside it. A rectangle without a width or a height, which
        /// a drag straight along one axis draws, covers one pixel that way.
        init?(rect: CGRect, viewSize: CGSize, scale: CGFloat) {
            guard viewSize.width > 0, viewSize.height > 0, scale > 0, rect.isNull == false, rect.isInfinite == false else {
                return nil
            }
            let bounds = CGRect(origin: .zero, size: viewSize)
            let inside = rect.standardized.intersection(bounds)
            guard inside.isNull == false else {
                return nil
            }

            // A rectangle of very many pixels is drawn coarser.
            var pixelsPerPoint = scale
            let pixels = max(inside.width, 1) * max(inside.height, 1) * scale * scale
            if pixels > SelectionVisibilityPass.maximumPixels {
                pixelsPerPoint = scale * (SelectionVisibilityPass.maximumPixels / pixels).squareRoot()
            }

            viewWidth = max(1, Int((viewSize.width * pixelsPerPoint).rounded(.up)))
            viewHeight = max(1, Int((viewSize.height * pixelsPerPoint).rounded(.up)))
            let left = Int((inside.minX * pixelsPerPoint).rounded(.down))
            let right = Int((inside.maxX * pixelsPerPoint).rounded(.up))
            // The rectangle is measured from the bottom, a texture from the top.
            let top = Int(((viewSize.height - inside.maxY) * pixelsPerPoint).rounded(.down))
            let bottom = Int(((viewSize.height - inside.minY) * pixelsPerPoint).rounded(.up))

            x = min(max(left, 0), viewWidth - 1)
            y = min(max(top, 0), viewHeight - 1)
            width = max(1, min(right, viewWidth) - x)
            height = max(1, min(bottom, viewHeight) - y)
        }
    }
}
