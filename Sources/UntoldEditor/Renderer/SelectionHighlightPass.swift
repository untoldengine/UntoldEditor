//
//  SelectionHighlightPass.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import MetalKit
import simd
import UntoldEngine

extension RenderPasses {
    /// The lines of the unit box on the GPU, made when first drawn.
    private static var selectionBoxLines: MTLBuffer?

    private static func selectionBoxLineBuffer() -> MTLBuffer? {
        if let selectionBoxLines {
            return selectionBoxLines
        }
        let lines = SelectionHighlights.unitBoxLines
        selectionBoxLines = renderInfo.device?.makeBuffer(
            bytes: lines,
            length: MemoryLayout<simd_float4>.stride * lines.count,
            options: .storageModeShared
        )
        selectionBoxLines?.label = "Selection box lines"
        return selectionBoxLines
    }

    /// Draws the box of every entity of a selection of several, in the
    /// highlight pass: the unit box, carried onto each entity's own.
    static func drawSelectionBoxes(_ boxes: [SelectionHighlightBox], with renderEncoder: MTLRenderCommandEncoder) {
        guard let lines = selectionBoxLineBuffer() else {
            return
        }
        renderEncoder.setVertexBuffer(lines, offset: 0, index: 0)

        for box in boxes {
            guard let placement = box.placement() else {
                continue
            }
            var model = placement.model
            var size = placement.size
            renderEncoder.setVertexBytes(&model, length: MemoryLayout<matrix_float4x4>.stride, index: 3)
            renderEncoder.setVertexBytes(&size, length: MemoryLayout<simd_float3>.stride, index: 4)
            renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: SelectionHighlights.unitBoxLines.count)
        }
    }
}
