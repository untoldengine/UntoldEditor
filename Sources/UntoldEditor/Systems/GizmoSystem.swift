//
//  GizmoSystem.swift
//
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

private enum GizmoDimensions {
    static let axisLength: Float = 0.9
    static let shaftRadius: Float = 0.01
    static let arrowHeight: Float = 0.2
    static let arrowRadius: Float = 0.09
    static let scaleCubeExtent: Float = 0.16
    static let rotateRingRadius: Float = 0.9
    static let rotateRingThickness: Float = 0.01
    static let rotateHitRingThickness: Float = 0.08
    static let rotateRingSegments: Int = 48
    static let rotateHitRingSegments: Int = 36
    static let directionHandleRadius: Float = 0.08
    static let directionHandleHitRadius: Float = 0.2
    static let directionHandleOffsetY: Float = -1.0
}

enum GizmoMode: String {
    case translate
    case rotate
    case scale

    init(name: String) {
        switch name {
        case "rotateGizmo":
            self = .rotate
        case "scaleGizmo":
            self = .scale
        default:
            self = .translate
        }
    }
}

final class GizmoHandleComponent: Component {
    var mode: TransformManipulationMode = .none
    var axis: TransformAxis = .none

    required init() {}
}

final class GizmoHitProxyComponent: Component {
    required init() {}
}

private struct GizmoHandleDescriptor {
    let mode: TransformManipulationMode
    let axis: TransformAxis
}

struct GizmoDragRay {
    let origin: simd_float3
    let direction: simd_float3
}

private struct GizmoDragState {
    let mode: TransformManipulationMode
    let axis: TransformAxis
    let axisWorldDirection: simd_float3
    let startAxisParameter: Float
    let startActiveLocalPosition: simd_float3
    let startGizmoWorldPosition: simd_float3
    var appliedAxisAmount: Float = 0.0

    var isAxisDriven: Bool {
        mode == .translate || mode == .scale
    }
}

private var gizmoDragState: GizmoDragState?
private var pendingGizmoDragRay: GizmoDragRay?

func gizmoRootWorldPosition() -> simd_float3 {
    guard parentEntityIdGizmo != .invalid else {
        return activeEntity == .invalid ? .zero : getPosition(entityId: activeEntity)
    }

    return getPosition(entityId: parentEntityIdGizmo)
}

func beginGizmoDrag(ray: GizmoDragRay) {
    guard activeEntity != .invalid,
          parentEntityIdGizmo != .invalid,
          let handleComponent = scene.get(component: GizmoHandleComponent.self, for: activeHitGizmoEntity)
    else {
        gizmoDragState = nil
        return
    }

    let axisDirection = worldDirection(for: handleComponent.axis)
    guard handleComponent.mode == .translate || handleComponent.mode == .scale,
          simd_length_squared(axisDirection) > 0.0001
    else {
        gizmoDragState = nil
        return
    }

    let normalizedRayDirection = normalizeOrNil(ray.direction) ?? ray.direction
    guard let startParameter = closestParameterOnAxis(
        axisPoint: gizmoRootWorldPosition(),
        axisDirection: axisDirection,
        rayOrigin: ray.origin,
        rayDirection: normalizedRayDirection
    ) else {
        gizmoDragState = nil
        return
    }

    gizmoDragState = GizmoDragState(
        mode: handleComponent.mode,
        axis: handleComponent.axis,
        axisWorldDirection: axisDirection,
        startAxisParameter: startParameter,
        startActiveLocalPosition: getLocalPosition(entityId: activeEntity),
        startGizmoWorldPosition: gizmoRootWorldPosition()
    )
}

func updateGizmoDrag(ray: GizmoDragRay) {
    guard var state = gizmoDragState,
          state.isAxisDriven
    else {
        return
    }

    let normalizedRayDirection = normalizeOrNil(ray.direction) ?? ray.direction
    guard let currentParameter = closestParameterOnAxis(
        axisPoint: state.startGizmoWorldPosition,
        axisDirection: state.axisWorldDirection,
        rayOrigin: ray.origin,
        rayDirection: normalizedRayDirection
    ) else {
        return
    }

    let axisAmount = currentParameter - state.startAxisParameter
    let incrementalAmount = axisAmount - state.appliedAxisAmount
    guard incrementalAmount.isFinite else {
        return
    }

    switch state.mode {
    case .translate:
        let translation = state.axisWorldDirection * axisAmount
        translateTo(entityId: activeEntity, position: state.startActiveLocalPosition + translation)
        translateTo(entityId: parentEntityIdGizmo, position: state.startGizmoWorldPosition + translation)

    case .scale:
        if hasComponent(entityId: activeEntity, componentType: LightComponent.self) {
            handleLightScaleInput(projectedAmount: incrementalAmount, axis: state.axisWorldDirection)
        } else {
            applyWorldSpaceScaleDelta(
                entityId: activeEntity,
                worldAxis: state.axisWorldDirection,
                projectedAmount: incrementalAmount
            )
        }

    default:
        break
    }

    state.appliedAxisAmount = axisAmount
    gizmoDragState = state
}

func queueGizmoDragUpdate(ray: GizmoDragRay) {
    pendingGizmoDragRay = ray
}

@discardableResult
func applyPendingGizmoDragUpdate() -> Bool {
    guard let ray = pendingGizmoDragRay else {
        return false
    }

    pendingGizmoDragRay = nil
    updateGizmoDrag(ray: ray)
    return true
}

func endGizmoDrag() {
    gizmoDragState = nil
    pendingGizmoDragRay = nil
}

func hasActiveAxisGizmoDrag() -> Bool {
    gizmoDragState?.isAxisDriven == true
}

func applyGizmoRotationDelta(entityId: EntityID, axis: simd_float3, degrees: Float) {
    guard entityId != .invalid,
          degrees.isFinite,
          simd_length_squared(axis) > 0.0001,
          let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId)
    else {
        return
    }

    let delta = simd_quatf(angle: degreesToRadians(degrees: degrees), axis: simd_normalize(axis))
    let currentRotation = normalizedRotationOrIdentity(localTransform.rotation)
    localTransform.rotation = simd_normalize(simd_mul(delta, currentRotation))
    translateTo(entityId: entityId, position: localTransform.position)
    syncStoredAxisRotationsFromQuaternion(entityId: entityId)
}

private func normalizedRotationOrIdentity(_ rotation: simd_quatf) -> simd_quatf {
    let lengthSquared = rotation.real * rotation.real + simd_length_squared(rotation.vector)
    guard lengthSquared.isFinite, lengthSquared > 0.0001 else {
        return simd_quatf(real: 1.0, imag: .zero)
    }

    return simd_normalize(rotation)
}

private func syncStoredAxisRotationsFromQuaternion(entityId: EntityID) {
    guard let localTransform = scene.get(component: LocalTransformComponent.self, for: entityId) else {
        return
    }

    let euler = transformQuaternionToEulerAngles(q: localTransform.rotation)
    localTransform.rotationX = euler.pitch
    localTransform.rotationY = euler.yaw
    localTransform.rotationZ = euler.roll
}

private func worldDirection(for axis: TransformAxis) -> simd_float3 {
    switch axis {
    case .x:
        return simd_float3(1.0, 0.0, 0.0)
    case .y:
        return simd_float3(0.0, 1.0, 0.0)
    case .z:
        return simd_float3(0.0, 0.0, 1.0)
    case .none:
        return .zero
    }
}

private func normalizeOrNil(_ value: simd_float3) -> simd_float3? {
    let lengthSquared = simd_length_squared(value)
    guard lengthSquared.isFinite, lengthSquared > 0.0001 else {
        return nil
    }
    return value / sqrt(lengthSquared)
}

private func closestParameterOnAxis(
    axisPoint: simd_float3,
    axisDirection: simd_float3,
    rayOrigin: simd_float3,
    rayDirection: simd_float3
) -> Float? {
    guard let axis = normalizeOrNil(axisDirection),
          let ray = normalizeOrNil(rayDirection)
    else {
        return nil
    }

    let w = axisPoint - rayOrigin
    let axisRayDot = simd_dot(axis, ray)
    let axisPointDot = simd_dot(axis, w)
    let rayPointDot = simd_dot(ray, w)
    let denominator = 1.0 - axisRayDot * axisRayDot

    guard abs(denominator) > 0.0001 else {
        return nil
    }

    let parameter = (axisRayDot * rayPointDot - axisPointDot) / denominator
    return parameter.isFinite ? parameter : nil
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

private func gizmoAnchorWorldPosition(entityId: EntityID) -> simd_float3 {
    guard let worldTransform = scene.get(component: WorldTransformComponent.self, for: entityId) else {
        return getPosition(entityId: entityId)
    }

    @inline(__always)
    func localBoundsCenter(for target: EntityID) -> simd_float3? {
        guard let localTransform = scene.get(component: LocalTransformComponent.self, for: target) else {
            return nil
        }
        return (localTransform.boundingBox.min + localTransform.boundingBox.max) * 0.5
    }

    var localCenter: simd_float3?

    if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
        localCenter = localBoundsCenter(for: entityId)
    } else {
        // Imported USD roots often have no RenderComponent, while renderable children carry bounds.
        // Match highlight behavior by anchoring from children's effective local bounds.
        var minBounds = simd_float3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = simd_float3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var foundRenderableChild = false

        let children = getEntityChildren(parentId: entityId)
        for childId in children {
            guard hasComponent(entityId: childId, componentType: RenderComponent.self),
                  let childTransform = scene.get(component: LocalTransformComponent.self, for: childId)
            else {
                continue
            }

            let translatedMin = childTransform.boundingBox.min + childTransform.position
            let translatedMax = childTransform.boundingBox.max + childTransform.position
            minBounds = simd_min(minBounds, translatedMin)
            maxBounds = simd_max(maxBounds, translatedMax)
            foundRenderableChild = true
        }

        if foundRenderableChild {
            localCenter = (minBounds + maxBounds) * 0.5
        }
    }

    guard let localCenter else {
        return getPosition(entityId: entityId)
    }

    let modelMatrix = simd_mul(worldTransform.space, matrix4x4Translation(localCenter.x, localCenter.y, localCenter.z))
    return simd_float3(modelMatrix.columns.3.x, modelMatrix.columns.3.y, modelMatrix.columns.3.z)
}

@discardableResult
private func createGizmoHandle(
    parentId: EntityID,
    name: String,
    meshes: [Mesh],
    localPosition: simd_float3,
    color: simd_float4,
    descriptor: GizmoHandleDescriptor,
    rotation: (angle: Float, axis: simd_float3)? = nil,
    isHitProxy: Bool = false
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
    registerComponent(entityId: handle, componentType: GizmoHandleComponent.self)
    if let handleComponent = scene.get(component: GizmoHandleComponent.self, for: handle) {
        handleComponent.mode = descriptor.mode
        handleComponent.axis = descriptor.axis
    }
    if isHitProxy {
        registerComponent(entityId: handle, componentType: GizmoHitProxyComponent.self)
    }
    applyGizmoHandleColor(entityId: handle, color: color)
    return handle
}

@discardableResult
private func makeDirectionHandle() -> EntityID {
    let handleColor = simd_float4(1.0, 1.0, 0.0, 1.0)
    let localPosition = initialLightDirectionHandleOffset()
    let visibleHandle = createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "directionHandle",
        meshes: BasicPrimitives.createSphere(extent: GizmoDimensions.directionHandleRadius, segments: [24, 12]),
        localPosition: localPosition,
        color: handleColor,
        descriptor: GizmoHandleDescriptor(mode: .lightRotate, axis: .none)
    )

    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "directionHandleHitProxy",
        meshes: BasicPrimitives.createSphere(extent: GizmoDimensions.directionHandleHitRadius, segments: [16, 8]),
        localPosition: localPosition,
        color: simd_float4(0.0, 0.0, 0.0, 0.0),
        descriptor: GizmoHandleDescriptor(mode: .lightRotate, axis: .none),
        isHitProxy: true
    )

    return visibleHandle
}

private func initialLightDirectionHandleOffset() -> simd_float3 {
    guard activeEntity != .invalid else {
        return simd_float3(0.0, GizmoDimensions.directionHandleOffsetY, 0.0)
    }

    let emissionDirection = getLightEmissionDirection(entityId: activeEntity)
    let handleDirection = simd_length(emissionDirection) > 0.0001 ? simd_normalize(emissionDirection) : simd_float3(0.0, -1.0, 0.0)
    return handleDirection * abs(GizmoDimensions.directionHandleOffsetY)
}

/// Repositions the light direction handle (and its hit proxy) to match the given light
/// entity's current orientation. Call this after changing a light's rotation through any
/// path other than dragging the handle itself (e.g. editing the Orientation fields in the
/// Inspector), so the gizmo doesn't go stale relative to the light it represents.
func syncLightDirectionHandleToActiveLight(entityId: EntityID) {
    guard entityId != .invalid,
          entityId == activeEntity,
          gizmoActive,
          parentEntityIdGizmo != .invalid,
          hasComponent(entityId: entityId, componentType: LightComponent.self)
    else {
        return
    }

    let localPosition = initialLightDirectionHandleOffset()

    for handle in getEntityChildren(parentId: parentEntityIdGizmo) {
        guard let handleComponent = scene.get(component: GizmoHandleComponent.self, for: handle),
              handleComponent.mode == .lightRotate, handleComponent.axis == .none
        else {
            continue
        }
        translateTo(entityId: handle, position: localPosition)
    }
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
            descriptor: GizmoHandleDescriptor(mode: .rotate, axis: axisForRotationHandleName(handleName)),
            rotation: rotation
        )
    }
}

private func makeRotationHitRing(
    handleName: String,
    axisA: simd_float3,
    axisB: simd_float3,
    startAngle: Float = 0.0,
    sweepAngle: Float = 2.0 * Float.pi
) {
    let fullTurn = 2.0 * Float.pi
    let normalizedSweep = max(0.0001, abs(sweepAngle))
    let segmentCount = max(1, Int(round(Float(GizmoDimensions.rotateHitRingSegments) * (normalizedSweep / fullTurn))))
    let radius = GizmoDimensions.rotateRingRadius
    let delta = sweepAngle / Float(segmentCount)
    let segmentLength = 2.0 * radius * sin(abs(delta) * 0.5)
    let descriptor = GizmoHandleDescriptor(mode: .rotate, axis: axisForRotationHandleName(handleName))

    @inline(__always)
    func makeHitSegmentMesh() -> [Mesh] {
        BasicPrimitives.createCylinder(
            height: segmentLength,
            radius: GizmoDimensions.rotateHitRingThickness,
            segments: [16, 1]
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
            name: "\(handleName)HitProxy",
            meshes: makeHitSegmentMesh(),
            localPosition: localPos,
            color: simd_float4(0.0, 0.0, 0.0, 0.0),
            descriptor: descriptor,
            rotation: rotation,
            isHitProxy: true
        )
    }
}

private func axisForRotationHandleName(_ handleName: String) -> TransformAxis {
    switch handleName {
    case "xAxisRotate":
        return .x
    case "yAxisRotate":
        return .y
    case "zAxisRotate":
        return .z
    default:
        return .none
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
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .x),
        rotation: (90.0, simd_float3(0.0, 0.0, 1.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(tipOffset, 0.0, 0.0),
        color: xColor,
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .x),
        rotation: (-90.0, simd_float3(0.0, 0.0, 1.0))
    )

    // Y axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisTranslate",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, halfShaft, 0.0),
        color: yColor,
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .y)
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(0.0, tipOffset, 0.0),
        color: yColor,
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .y)
    )

    // Z axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisTranslate",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, 0.0, halfShaft),
        color: zColor,
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .z),
        rotation: (90.0, simd_float3(1.0, 0.0, 0.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisTranslate",
        meshes: makeArrowMeshes(),
        localPosition: simd_float3(0.0, 0.0, tipOffset),
        color: zColor,
        descriptor: GizmoHandleDescriptor(mode: .translate, axis: .z),
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
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .x),
        rotation: (90.0, simd_float3(0.0, 0.0, 1.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "xAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(cubeCenterOffset, 0.0, 0.0),
        color: xColor,
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .x)
    )

    // Y axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisScale",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, halfShaft, 0.0),
        color: yColor,
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .y)
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "yAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(0.0, cubeCenterOffset, 0.0),
        color: yColor,
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .y)
    )

    // Z axis
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisScale",
        meshes: makeShaftMeshes(),
        localPosition: simd_float3(0.0, 0.0, halfShaft),
        color: zColor,
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .z),
        rotation: (90.0, simd_float3(1.0, 0.0, 0.0))
    )
    createGizmoHandle(
        parentId: parentEntityIdGizmo,
        name: "zAxisScale",
        meshes: makeTipCubeMeshes(),
        localPosition: simd_float3(0.0, 0.0, cubeCenterOffset),
        color: zColor,
        descriptor: GizmoHandleDescriptor(mode: .scale, axis: .z)
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
    makeRotationHitRing(
        handleName: "xAxisRotate",
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
    makeRotationHitRing(
        handleName: "yAxisRotate",
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
    makeRotationHitRing(
        handleName: "zAxisRotate",
        axisA: simd_float3(1.0, 0.0, 0.0),
        axisB: simd_float3(0.0, 1.0, 0.0),
        startAngle: positiveArcStart,
        sweepAngle: positiveArcSweep
    )
}

func createGizmo(name: String) {
    createGizmo(mode: GizmoMode(name: name))
}

func createGizmo(mode: GizmoMode) {
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

    translateTo(entityId: parentEntityIdGizmo, position: gizmoAnchorWorldPosition(entityId: activeEntity))

    switch mode {
    case .translate:
        makeTranslateGizmo()
    case .rotate:
        makeRotationGizmo()
    case .scale:
        makeScaleGizmo()
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

        guard let editorController else {
            return
        }

        guard let handleComponent = scene.get(component: GizmoHandleComponent.self, for: entityId) else {
            activeHitGizmoEntity = .invalid
            editorController.activeMode = .none
            editorController.activeAxis = .none
            return
        }

        editorController.activeAxis = handleComponent.axis
        editorController.activeMode = handleComponent.mode
    #endif
}

func hitGizmoToolAxis(entityId: EntityID) -> Bool {
    if entityId == .invalid {
        return false
    }

    return scene.get(component: GizmoHandleComponent.self, for: entityId) != nil
}

func removeGizmo() {
    if parentEntityIdGizmo != .invalid {
        destroyEntity(entityId: parentEntityIdGizmo)
        parentEntityIdGizmo = .invalid
    }

    directionHandleEntityId = .invalid
    gizmoActive = false
}
