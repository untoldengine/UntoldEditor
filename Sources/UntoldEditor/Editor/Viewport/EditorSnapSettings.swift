//
//  EditorSnapSettings.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import Foundation
import UntoldEngine

/// The steps a gizmo drag lands on when snapping is on: a grid for moves, an
/// angle for rotations and an amount for scales, each with its own switch.
/// Persisted across launches.
final class EditorSnapSettings: ObservableObject {
    static let shared = EditorSnapSettings(defaults: .standard)

    static let gridSteps: [Float] = [0.1, 0.25, 0.5, 1]
    static let rotationSteps: [Float] = [5, 15, 45, 90]
    static let scaleSteps: [Float] = [0.1, 0.25]
    static let keyPrefix = "editor.snap."

    @Published var isEnabled: Bool {
        didSet { persist() }
    }

    @Published var snapsMove: Bool {
        didSet { persist() }
    }

    @Published var snapsRotate: Bool {
        didSet { persist() }
    }

    @Published var snapsScale: Bool {
        didSet { persist() }
    }

    @Published var gridStep: Float {
        didSet { persist() }
    }

    @Published var rotationStep: Float {
        didSet { persist() }
    }

    @Published var scaleStep: Float {
        didSet { persist() }
    }

    private let defaults: UserDefaults?

    /// `defaults` nil keeps nothing, for tests.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        func flag(_ name: String, _ fallback: Bool) -> Bool {
            defaults?.object(forKey: Self.keyPrefix + name) as? Bool ?? fallback
        }
        func step(_ name: String, _ choices: [Float], _ fallback: Float) -> Float {
            let stored = defaults?.object(forKey: Self.keyPrefix + name) as? Float
            return stored.flatMap { choices.contains($0) ? $0 : nil } ?? fallback
        }
        isEnabled = flag("enabled", false)
        snapsMove = flag("move", true)
        snapsRotate = flag("rotate", true)
        snapsScale = flag("scale", true)
        gridStep = step("gridStep", Self.gridSteps, 0.5)
        rotationStep = step("rotationStep", Self.rotationSteps, 15)
        scaleStep = step("scaleStep", Self.scaleSteps, 0.25)
    }

    /// The step a drag of this kind snaps to, or nil when it does not snap.
    func step(for mode: TransformManipulationMode) -> Float? {
        guard isEnabled else {
            return nil
        }
        switch mode {
        case .translate: return snapsMove ? gridStep : nil
        case .rotate: return snapsRotate ? rotationStep : nil
        case .scale: return snapsScale ? scaleStep : nil
        default: return nil
        }
    }

    /// The amount a drag of this kind lands on: the nearest step, or the
    /// amount itself when the kind does not snap.
    func snapped(_ amount: Float, for mode: TransformManipulationMode) -> Float {
        step(for: mode).map { Self.quantize(amount, step: $0) } ?? amount
    }

    /// The nearest multiple of `step`.
    static func quantize(_ amount: Float, step: Float) -> Float {
        guard step > 0, amount.isFinite else {
            return amount
        }
        return (amount / step).rounded() * step
    }

    /// The header pill: the grid step while snapping is on.
    var summary: String {
        isEnabled ? "Snap \(Self.format(gridStep)) m" : "Snap off"
    }

    /// "0.25" or "1", without a trailing ".0".
    static func format(_ step: Float) -> String {
        step == step.rounded() ? String(Int(step)) : String(step)
    }

    private func persist() {
        guard let defaults else { return }
        defaults.set(isEnabled, forKey: Self.keyPrefix + "enabled")
        defaults.set(snapsMove, forKey: Self.keyPrefix + "move")
        defaults.set(snapsRotate, forKey: Self.keyPrefix + "rotate")
        defaults.set(snapsScale, forKey: Self.keyPrefix + "scale")
        defaults.set(gridStep, forKey: Self.keyPrefix + "gridStep")
        defaults.set(rotationStep, forKey: Self.keyPrefix + "rotationStep")
        defaults.set(scaleStep, forKey: Self.keyPrefix + "scaleStep")
    }
}
