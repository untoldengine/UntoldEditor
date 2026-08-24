//
//  EditorUndoManager.swift
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
import SwiftUI
import UntoldEngine

protocol EditorUndoCommand {
    var name: String { get }
    func undo()
    func redo()
}

struct EditorTransformSnapshot: Equatable {
    var position: simd_float3
    var rotation: simd_float3
    var scale: simd_float3

    init(entityId: EntityID) {
        position = getLocalPosition(entityId: entityId)
        rotation = getAxisRotations(entityId: entityId)
        scale = getScale(entityId: entityId)
    }

    func apply(to entityId: EntityID) {
        guard hasComponent(entityId: entityId, componentType: LocalTransformComponent.self) else {
            return
        }

        translateTo(entityId: entityId, position: position)
        applyAxisRotations(entityId: entityId, axis: rotation)
        scaleTo(entityId: entityId, scale: scale)
    }
}

struct EditorNameChangeCommand: EditorUndoCommand {
    let entityId: EntityID
    let oldName: String
    let newName: String

    var name: String {
        "Rename Entity"
    }

    func undo() {
        setEntityName(entityId: entityId, name: oldName)
    }

    func redo() {
        setEntityName(entityId: entityId, name: newName)
    }
}

struct EditorTransformChangeCommand: EditorUndoCommand {
    let entityId: EntityID
    let before: EditorTransformSnapshot
    let after: EditorTransformSnapshot

    var name: String {
        "Transform Entity"
    }

    func undo() {
        before.apply(to: entityId)
    }

    func redo() {
        after.apply(to: entityId)
    }
}

struct EditorValueChangeCommand<Value: Equatable>: EditorUndoCommand {
    let name: String
    let oldValue: Value
    let newValue: Value
    let apply: (Value) -> Void

    func undo() {
        apply(oldValue)
    }

    func redo() {
        apply(newValue)
    }
}

struct EditorPostFXSnapshot: Equatable {
    var colorGradingEnabled: Bool
    var exposure: Float
    var brightness: Float
    var contrast: Float
    var saturation: Float
    var temperature: Float
    var tint: Float
    var bloomEnabled: Bool
    var bloomThreshold: Float
    var bloomIntensity: Float
    var vignetteEnabled: Bool
    var vignetteIntensity: Float
    var vignetteRadius: Float
    var vignetteSoftness: Float
    var chromaticAberrationEnabled: Bool
    var chromaticAberrationIntensity: Float
    var depthOfFieldEnabled: Bool
    var focusDistance: Float
    var focusRange: Float
    var maxBlur: Float
    var ssaoEnabled: Bool
    var ssaoRadius: Float
    var ssaoBias: Float
    var ssaoIntensity: Float

    init() {
        colorGradingEnabled = ColorGradingParams.shared.enabled
        exposure = ColorGradingParams.shared.exposure
        brightness = ColorGradingParams.shared.brightness
        contrast = ColorGradingParams.shared.contrast
        saturation = ColorGradingParams.shared.saturation
        temperature = ColorGradingParams.shared.temperature
        tint = ColorGradingParams.shared.tint

        bloomEnabled = BloomThresholdParams.shared.enabled
        bloomThreshold = BloomThresholdParams.shared.threshold
        bloomIntensity = BloomThresholdParams.shared.intensity

        vignetteEnabled = VignetteParams.shared.enabled
        vignetteIntensity = VignetteParams.shared.intensity
        vignetteRadius = VignetteParams.shared.radius
        vignetteSoftness = VignetteParams.shared.softness

        chromaticAberrationEnabled = ChromaticAberrationParams.shared.enabled
        chromaticAberrationIntensity = ChromaticAberrationParams.shared.intensity

        depthOfFieldEnabled = DepthOfFieldParams.shared.enabled
        focusDistance = DepthOfFieldParams.shared.focusDistance
        focusRange = DepthOfFieldParams.shared.focusRange
        maxBlur = DepthOfFieldParams.shared.maxBlur

        ssaoEnabled = SSAOParams.shared.enabled
        ssaoRadius = SSAOParams.shared.radius
        ssaoBias = SSAOParams.shared.bias
        ssaoIntensity = SSAOParams.shared.intensity
    }

    func apply() {
        ColorGradingParams.shared.enabled = colorGradingEnabled
        ColorGradingParams.shared.exposure = exposure
        ColorGradingParams.shared.brightness = brightness
        ColorGradingParams.shared.contrast = contrast
        ColorGradingParams.shared.saturation = saturation
        ColorGradingParams.shared.temperature = temperature
        ColorGradingParams.shared.tint = tint

        BloomThresholdParams.shared.enabled = bloomEnabled
        BloomThresholdParams.shared.threshold = bloomThreshold
        BloomThresholdParams.shared.intensity = bloomIntensity

        VignetteParams.shared.enabled = vignetteEnabled
        VignetteParams.shared.intensity = vignetteIntensity
        VignetteParams.shared.radius = vignetteRadius
        VignetteParams.shared.softness = vignetteSoftness

        ChromaticAberrationParams.shared.enabled = chromaticAberrationEnabled
        ChromaticAberrationParams.shared.intensity = chromaticAberrationIntensity

        DepthOfFieldParams.shared.enabled = depthOfFieldEnabled
        DepthOfFieldParams.shared.focusDistance = focusDistance
        DepthOfFieldParams.shared.focusRange = focusRange
        DepthOfFieldParams.shared.maxBlur = maxBlur

        SSAOParams.shared.enabled = ssaoEnabled
        SSAOParams.shared.radius = ssaoRadius
        SSAOParams.shared.bias = ssaoBias
        SSAOParams.shared.intensity = ssaoIntensity
    }
}

struct EditorPostFXChangeCommand: EditorUndoCommand {
    let name: String
    let before: EditorPostFXSnapshot
    let after: EditorPostFXSnapshot

    func undo() {
        before.apply()
    }

    func redo() {
        after.apply()
    }
}

final class EditorUndoManager: ObservableObject {
    static let shared = EditorUndoManager()

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var undoStack: [EditorUndoCommand] = []
    private var redoStack: [EditorUndoCommand] = []
    private var transformEditStart: [EntityID: EditorTransformSnapshot] = [:]
    private var isReplaying = false

    var onStateRestored: (() -> Void)?

    func register(_ command: EditorUndoCommand) {
        guard isReplaying == false else {
            return
        }

        undoStack.append(command)
        redoStack.removeAll()
        updateAvailability()
    }

    func registerNameChange(entityId: EntityID, oldName: String, newName: String) {
        guard oldName != newName else {
            return
        }

        register(EditorNameChangeCommand(entityId: entityId, oldName: oldName, newName: newName))
    }

    func registerTransformChange(entityId: EntityID, before: EditorTransformSnapshot, after: EditorTransformSnapshot) {
        guard before != after else {
            return
        }

        register(EditorTransformChangeCommand(entityId: entityId, before: before, after: after))
    }

    func beginTransformEdit(entityId: EntityID) {
        guard isReplaying == false,
              hasComponent(entityId: entityId, componentType: LocalTransformComponent.self),
              transformEditStart[entityId] == nil
        else {
            return
        }

        transformEditStart[entityId] = EditorTransformSnapshot(entityId: entityId)
    }

    func commitTransformEdit(entityId: EntityID) {
        guard let before = transformEditStart.removeValue(forKey: entityId),
              hasComponent(entityId: entityId, componentType: LocalTransformComponent.self)
        else {
            return
        }

        registerTransformChange(
            entityId: entityId,
            before: before,
            after: EditorTransformSnapshot(entityId: entityId)
        )
    }

    func registerValueChange<Value: Equatable>(
        name: String,
        oldValue: Value,
        newValue: Value,
        apply: @escaping (Value) -> Void
    ) {
        guard oldValue != newValue else {
            return
        }

        register(EditorValueChangeCommand(name: name, oldValue: oldValue, newValue: newValue, apply: apply))
    }

    func registerPostFXChange(name: String, before: EditorPostFXSnapshot, after: EditorPostFXSnapshot) {
        guard before != after else {
            return
        }

        register(EditorPostFXChangeCommand(name: name, before: before, after: after))
    }

    func undo() {
        guard let command = undoStack.popLast() else {
            return
        }

        replay {
            command.undo()
        }
        redoStack.append(command)
        updateAvailability()
    }

    func redo() {
        guard let command = redoStack.popLast() else {
            return
        }

        replay {
            command.redo()
        }
        undoStack.append(command)
        updateAvailability()
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
        transformEditStart.removeAll()
        updateAvailability()
    }

    private func replay(_ operation: () -> Void) {
        isReplaying = true
        operation()
        isReplaying = false
        onStateRestored?()
    }

    private func updateAvailability() {
        canUndo = undoStack.isEmpty == false
        canRedo = redoStack.isEmpty == false
    }
}
