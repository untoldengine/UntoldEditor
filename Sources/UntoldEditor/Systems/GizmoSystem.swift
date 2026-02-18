//
//  GizmoSystem.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation
import simd
import UntoldEngine

private func applyDefaultGizmoOrientation(entityId: EntityID) {
    // Keep gizmo axis meshes aligned with engine/world axes.
    rotateTo(entityId: entityId, angle: -90.0, axis: simd_float3(1.0, 0.0, 0.0))
}

private enum GizmoDimensions {
    static let axisLength: Float = 0.9
    static let shaftRadius: Float = 0.01
    static let arrowHeight: Float = 0.2
    static let arrowRadius: Float = 0.09
    static let scaleCubeExtent: Float = 0.16
    static let rotateRingRadius: Float = 0.9
    static let rotateRingThickness: Float = 0.01
    static let rotateRingSegments: Int = 48
    static let directionHandleRadius: Float = 0.08
    static let directionHandleOffsetY: Float = -1.0
}

private func applyGizmoHandleColor(entityId: EntityID, color: simd_float4) {
    guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId) else {
        return
    }

    for meshIndex in renderComponent.mesh.indices {
        for subMeshIndex in renderComponent.mesh[meshIndex].submeshes.indices {
            guard var material = renderComponent.mesh[meshIndex].submeshes[subMeshIndex].material else {
                continue
            }

            material.baseColorValue = color
            material.emissiveValue = simd_float3(color.x, color.y, color.z)
            material.interactWithLight = false
            renderComponent.mesh[meshIndex].submeshes[subMeshIndex].material = material
        }
    }
}

@discardableResult
private func createGizmoHandle(
    parentId: EntityID,
    name: String,
    meshes: [Mesh],
    localPosition: simd_float3,
    color: simd_float4,
    rotation: (angle: Float, axis: simd_float3)? = nil
) -> EntityID {
    let handle = createEntity()
    setEntityName(entityId: handle, name: name)
    setEntityMeshDirect(entityId: handle, meshes: meshes, assetName: name)
    setParent(childId: handle, parentId: parentId)
    translateTo(entityId: handle, position: localPosition)
    if let rotation {
        rotateTo(entityId: handle, angle: rotation.angle, axis: rotation.axis)
    }
    registerComponent(entityId: handle, componentType: GizmoComponent.self)
    applyGizmoHandleColor(entityId: handle, color: color)
    return handle
}

@discardableResult
private func makeDirectionHandle() -> EntityID {
    let handleColor = simd_float4(1.0, 1.0, 0.0, 1.0)
    return createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "directionHandle",
        meshes: BasicPrimitives.createSphere(extent: GizmoDimensions.directionHandleRadius, segments: [24, 12]),
        localPosition: simd_float3(0.0, GizmoDimensions.directionHandleOffsetY, 0.0),
        color: handleColor
    )
}

private func rotationFromYAxis(to direction: simd_float3) -> (angle: Float, axis: simd_float3)? {
    let up = simd_float3(0.0, 1.0, 0.0)
    let dirLength = simd_length(direction)
    if dirLength < 0.0001 {
        return nil
    }

    let dir = simd_normalize(direction)
    let dotValue = simd_dot(up, dir)
    let clampedDot = max(-1.0, min(1.0, dotValue))
    let angleRadians = acos(clampedDot)

    if angleRadians < 0.0001 {
        return nil
    }

    var axis = simd_cross(up, dir)
    if simd_length(axis) < 0.0001 {
        axis = simd_float3(1.0, 0.0, 0.0)
    } else {
        axis = simd_normalize(axis)
    }

    let angleDegrees = angleRadians * (180.0 / Float.pi)
    return (angleDegrees, axis)
}

private func makeRotationRing(
    handleName: String,
    color: simd_float4,
    axisA: simd_float3,
    axisB: simd_float3,
    startAngle: Float = 0.0,
    sweepAngle: Float = 2.0 * Float.pi
) {
    let fullTurn = 2.0 * Float.pi
    let normalizedSweep = max(0.0001, abs(sweepAngle))
    let segmentCount = max(1, Int(round(Float(GizmoDimensions.rotateRingSegments) * (normalizedSweep / fullTurn))))
    let radius = GizmoDimensions.rotateRingRadius
    let delta = sweepAngle / Float(segmentCount)
    let segmentLength = 2.0 * radius * sin(abs(delta) * 0.5) * 0.9

    @inline(__always)
    func makeRingSegmentMesh() -> [Mesh] {
        BasicPrimitives.createCylinder(
            height: segmentLength,
            radius: GizmoDimensions.rotateRingThickness,
            segments: [12, 1]
        )
    }

    for i in 0 ..< segmentCount {
        let theta = startAngle + (Float(i) + 0.5) * delta
        let c = cos(theta)
        let s = sin(theta)

        let localPos = axisA * (radius * c) + axisB * (radius * s)
        let tangent = axisA * -s + axisB * c
        let rotation = rotationFromYAxis(to: tangent)

        createGizmoHandle(
            parentId: parentEntityIdGizmo,
            name: handleName,
            meshes: makeRingSegmentMesh(),
            localPosition: localPos,
            color: color,
            rotation: rotation
        )
    }
}

func makeTranslateGizmo() {
    @inline(__always)
    func makeShaftMeshes() -> [Mesh] {
        BasicPrimitives.createCylinder(
            height: GizmoDimensions.axisLength,
            radius: GizmoDimensions.shaftRadius,
            segments: [16, 1]
        )
    }

    @inline(__always)
    func makeArrowMeshes() -> [Mesh] {
        BasicPrimitives.createCone(
            height: GizmoDimensions.arrowHeight,
            radius: GizmoDimensions.arrowRadius,
            segments: [20, 1]
        )
    }

    let halfShaft = GizmoDimensions.axisLength * 0.5
    let tipOffset = GizmoDimensions.axisLength + GizmoDimensions.arrowHeight

    // X axis
    let xColor = simd_float4(1.0, 0.0, 0.0, 1.0)
    let yColor = simd_float4(0.0, 1.0, 0.0, 1.0)
    let zColor = simd_float4(0.0, 0.0, 1.0, 1.0)

    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisTranslate",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(halfShaft, 0.0, 0.0),
        color: xColor,
        rotation: (90.0, simd_float3(0.0, 0.0, 1.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(tipOffset, 0.0, 0.0),
        color: xColor,
        rotation: (-90.0, simd_float3(0.0, 0.0, 1.0))
    )

    // Y axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisTranslate",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, halfShaft, 0.0),
        color: yColor
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(0.0, tipOffset, 0.0),
        color: yColor
    )

    // Z axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisTranslate",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, 0.0, halfShaft),
        color: zColor,
        rotation: (90.0, simd_float3(1.0, 0.0, 0.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(0.0, 0.0, tipOffset),
        color: zColor,
        rotation: (90.0, simd_float3(1.0, 0.0, 0.0))
    )
}

func makeScaleGizmo() {
    @inline(__always)
    func makeShaftMeshes() -> [Mesh] {
        BasicPrimitives.createCylinder(
            height: GizmoDimensions.axisLength,
            radius: GizmoDimensions.shaftRadius,
            segments: [16, 1]
        )
    }

    @inline(__always)
    func makeTipCubeMeshes() -> [Mesh] {
        BasicPrimitives.createCube(extent: GizmoDimensions.scaleCubeExtent)
    }

    let halfShaft = GizmoDimensions.axisLength * 0.5
    let cubeCenterOffset = GizmoDimensions.axisLength + (GizmoDimensions.scaleCubeExtent * 0.5)

    // X axis
    let xColor = simd_float4(1.0, 0.0, 0.0, 1.0)
    let yColor = simd_float4(0.0, 1.0, 0.0, 1.0)
    let zColor = simd_float4(0.0, 0.0, 1.0, 1.0)

    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisScale",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(halfShaft, 0.0, 0.0),
        color: xColor,
        rotation: (90.0, simd_float3(0.0, 0.0, 1.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(cubeCenterOffset, 0.0, 0.0),
        color: xColor
    )

    // Y axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisScale",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, halfShaft, 0.0),
        color: yColor
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(0.0, cubeCenterOffset, 0.0),
        color: yColor
    )

    // Z axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisScale",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, 0.0, halfShaft),
        color: zColor,
        rotation: (90.0, simd_float3(1.0, 0.0, 0.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(0.0, 0.0, cubeCenterOffset),
        color: zColor
    )
}

func makeRotationGizmo() {
    let xColor = simd_float4(1.0, 0.0, 0.0, 1.0)
    let yColor = simd_float4(0.0, 1.0, 0.0, 1.0)
    let zColor = simd_float4(0.0, 0.0, 1.0, 1.0)
    let positiveArcStart: Float = 0.0
    let positiveArcSweep = Float.pi * 0.5

    // X-axis rotation ring (YZ plane)
    makeRotationRing(
        handleName: "xAxisRotate",
        color: xColor,
        axisA: simd_float3(0.0, 1.0, 0.0),
        axisB: simd_float3(0.0, 0.0, 1.0),
        startAngle: positiveArcStart,
        sweepAngle: positiveArcSweep
    )

    // Y-axis rotation ring (XZ plane)
    makeRotationRing(
        handleName: "yAxisRotate",
        color: yColor,
        axisA: simd_float3(1.0, 0.0, 0.0),
        axisB: simd_float3(0.0, 0.0, 1.0),
        startAngle: positiveArcStart,
        sweepAngle: positiveArcSweep
    )

    // Z-axis rotation ring (XY plane)
    makeRotationRing(
        handleName: "zAxisRotate",
        color: zColor,
        axisA: simd_float3(1.0, 0.0, 0.0),
        axisB: simd_float3(0.0, 1.0, 0.0),
        startAngle: positiveArcStart,
        sweepAngle: positiveArcSweep
    )
}

func createGizmo(name: String) {
    removeGizmo()
    directionHandleEntityId = .invalid

    if activeEntity == .invalid {
        return
    }

    // create parent gizmo entity
    parentEntityIdGizmo = createEntity()

    registerTransformComponent(entityId: parentEntityIdGizmo)
    registerSceneGraphComponent(entityId: parentEntityIdGizmo)
    registerComponent(entityId: parentEntityIdGizmo, componentType: GizmoComponent.self)

    translateTo(entityId: parentEntityIdGizmo, position: getPosition(entityId: activeEntity))

    if name == "translateGizmo" {
        makeTranslateGizmo()
    } else if name == "rotateGizmo" {
        makeRotationGizmo()
    } else if name == "scaleGizmo" {
        makeScaleGizmo()
    } else {
        makeTranslateGizmo()
    }

    if hasComponent(entityId: activeEntity, componentType: LightComponent.self) {
        directionHandleEntityId = makeDirectionHandle()
    }

    gizmoActive = true
}

func processGizmoAction(entityId: EntityID) {
    #if canImport(AppKit)
        if entityId == .invalid {
            return
        }

        if getEntityName(entityId: entityId) == "xAxisTranslate" {
            editorController!.activeAxis = .x
            editorController!.activeMode = .translate
        } else if getEntityName(entityId: entityId) == "yAxisTranslate" {
            editorController!.activeAxis = .y
            editorController!.activeMode = .translate
        } else if getEntityName(entityId: entityId) == "zAxisTranslate" {
            editorController!.activeAxis = .z
            editorController!.activeMode = .translate
        } else if getEntityName(entityId: entityId) == "yAxisRotate" {
            editorController!.activeAxis = .y
            editorController!.activeMode = .rotate
        } else if getEntityName(entityId: entityId) == "xAxisRotate" {
            editorController!.activeAxis = .x
            editorController!.activeMode = .rotate
        } else if getEntityName(entityId: entityId) == "zAxisRotate" {
            editorController!.activeAxis = .z
            editorController!.activeMode = .rotate
        } else if getEntityName(entityId: entityId) == "xAxisScale" {
            editorController!.activeAxis = .x
            editorController!.activeMode = .scale
        } else if getEntityName(entityId: entityId) == "yAxisScale" {
            editorController!.activeAxis = .y
            editorController!.activeMode = .scale
        } else if getEntityName(entityId: entityId) == "zAxisScale" {
            editorController!.activeAxis = .z
            editorController!.activeMode = .scale
        } else if getEntityName(entityId: entityId) == "directionHandle" {
            editorController!.activeMode = .lightRotate
            editorController!.activeAxis = .none
        } else {
            activeHitGizmoEntity = .invalid
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
        }
    #endif
}

func hitGizmoToolAxis(entityId: EntityID) -> Bool {
    if entityId == .invalid {
        return false
    }

    let name = getEntityName(entityId: entityId)

    let validNames: Set<String> = [
        "xAxisTranslate", "yAxisTranslate", "zAxisTranslate",
        "xAxisRotate", "yAxisRotate", "zAxisRotate",
        "xAxisScale", "yAxisScale", "zAxisScale",
        "directionHandle",
    ]

    if validNames.contains(name) {
        return true
    } else {
        return false
    }
}

func removeGizmo() {
    if parentEntityIdGizmo != .invalid {
        destroyEntity(entityId: parentEntityIdGizmo)
        parentEntityIdGizmo = .invalid
    }

    directionHandleEntityId = .invalid
    gizmoActive = false
}
