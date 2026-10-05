//
//  SelectionHighlights.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import simd
import UntoldEngine

/// The box the highlight pass draws around one entity of a selection of
/// several. It is given in the entity's own space, so it follows the entity
/// as the gizmo moves it, with no need to be taken again.
struct SelectionHighlightBox: Equatable {
    /// The side of the box drawn where an entity that draws nothing stands.
    static let pointExtent: Float = 0.5

    let entityId: EntityID
    let minimum: simd_float3
    let maximum: simd_float3
    /// True for an entity that draws nothing, such as a light: its box stands
    /// where the entity does, along the world's axes and always the same size.
    let isPoint: Bool

    static func point(entityId: EntityID) -> SelectionHighlightBox {
        let half = simd_float3(repeating: pointExtent / 2)
        return SelectionHighlightBox(entityId: entityId, minimum: -half, maximum: half, isPoint: true)
    }

    /// The matrix and the size that carry the unit box, from zero to one
    /// along each axis, onto this one; nil once the entity has left the scene.
    func placement() -> (model: simd_float4x4, size: simd_float3)? {
        guard let world = scene.get(component: WorldTransformComponent.self, for: entityId)?.space else {
            return nil
        }
        let size = maximum - minimum
        if isPoint {
            let position = simd_float3(world.columns.3.x, world.columns.3.y, world.columns.3.z) + minimum
            return (matrix4x4Translation(position.x, position.y, position.z), size)
        }
        return (simd_mul(world, matrix4x4Translation(minimum.x, minimum.y, minimum.z)), size)
    }
}

/// The boxes of a selection of several entities. The selection writes them
/// and the highlight pass reads them at every frame; with one entity selected
/// there are none, and the pass draws that entity's box as it always did.
final class SelectionHighlights {
    static let shared = SelectionHighlights()

    private let lock = NSLock()
    private var stored: [SelectionHighlightBox] = []

    var boxes: [SelectionHighlightBox] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            stored = newValue
        }
    }

    /// The edges of the unit box, from zero to one along each axis, as the
    /// twelve lines the highlight pass draws.
    static let unitBoxLines: [simd_float4] = {
        let corner: (Float, Float, Float) -> simd_float4 = { simd_float4($0, $1, $2, 1) }
        return [
            // The bottom face
            corner(0, 0, 0), corner(1, 0, 0),
            corner(1, 0, 0), corner(1, 0, 1),
            corner(1, 0, 1), corner(0, 0, 1),
            corner(0, 0, 1), corner(0, 0, 0),
            // The top face
            corner(0, 1, 0), corner(1, 1, 0),
            corner(1, 1, 0), corner(1, 1, 1),
            corner(1, 1, 1), corner(0, 1, 1),
            corner(0, 1, 1), corner(0, 1, 0),
            // The edges between them
            corner(0, 0, 0), corner(0, 1, 0),
            corner(1, 0, 0), corner(1, 1, 0),
            corner(1, 0, 1), corner(1, 1, 1),
            corner(0, 0, 1), corner(0, 1, 1),
        ]
    }()
}
