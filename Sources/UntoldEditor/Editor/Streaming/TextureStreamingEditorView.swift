//
//  TextureStreamingEditorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

struct TextureStreamingEditorView: View {
    private enum ProfileOption: String, CaseIterable, Identifiable {
        case detailed = "Detailed"
        case superdetailed = "Super Detailed"
        case openWorld = "Open World"
        case balanced = "Balanced"
        case tiled = "Tiled"

        var id: String { rawValue }

        var engineProfile: TextureStreamingSystem.Profile {
            switch self {
            case .detailed: return .detailed
            case .superdetailed: return .superdetailed
            case .openWorld: return .openWorld
            case .balanced: return .balanced
            case .tiled: return .tiled
            }
        }
    }

    @State private var selectedProfile: ProfileOption = .balanced
    @State private var enabled = TextureStreamingSystem.shared.enabled
    @State private var upgradeRadius = TextureStreamingSystem.shared.upgradeRadius
    @State private var downgradeRadius = TextureStreamingSystem.shared.downgradeRadius
    @State private var maxTextureDimension = Float(TextureStreamingSystem.shared.maxTextureDimension)
    @State private var minimumTextureDimension = Float(TextureStreamingSystem.shared.minimumTextureDimension)
    @State private var hysteresisFraction = TextureStreamingSystem.shared.hysteresisFraction
    @State private var maxConcurrentOps = Float(TextureStreamingSystem.shared.maxConcurrentOps)
    @State private var updateInterval = TextureStreamingSystem.shared.updateInterval

    private func refreshFromEngine() {
        let system = TextureStreamingSystem.shared
        enabled = system.enabled
        upgradeRadius = system.upgradeRadius
        downgradeRadius = system.downgradeRadius
        maxTextureDimension = Float(system.maxTextureDimension)
        minimumTextureDimension = Float(system.minimumTextureDimension)
        hysteresisFraction = system.hysteresisFraction
        maxConcurrentOps = Float(system.maxConcurrentOps)
        updateInterval = system.updateInterval
    }

    private func selectProfile(_ newValue: ProfileOption) {
        let oldValue = selectedProfile
        guard oldValue != newValue else { return }
        selectedProfile = newValue
        TextureStreamingSystem.shared.apply(newValue.engineProfile)
        refreshFromEngine()
        EditorSceneDirtyState.shared.markDirty()
        EditorUndoManager.shared.registerValueChange(
            name: "Apply \(newValue.rawValue) Streaming Profile",
            oldValue: oldValue,
            newValue: newValue,
            apply: { option in
                selectedProfile = option
                TextureStreamingSystem.shared.apply(option.engineProfile)
                refreshFromEngine()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header

            HStack(spacing: 6) {
                Text("Texture Streaming")
                    .font(.headline)
                    .foregroundColor(.editorTextPrimary)
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Enable Toggle

            UndoableEffectToggle(
                undoName: "Toggle Texture Streaming",
                isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        enabled = newValue
                        TextureStreamingSystem.shared.enabled = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )
            ) {
                Label("Enable Streaming", systemImage: enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
            }

            Divider()

            // MARK: - Profile Picker

            VStack(alignment: .leading, spacing: 6) {
                Text("Profile")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)

                Picker("Profile", selection: Binding(
                    get: { selectedProfile },
                    set: selectProfile
                )) {
                    ForEach(ProfileOption.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .help("Apply a built-in tuning profile; individual parameters below can still be overridden afterward")
            }

            Divider()

            // MARK: - Parameters

            VStack(alignment: .leading, spacing: 6) {
                Text("Parameters")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)

                UndoableEffectSlider(
                    label: "Upgrade Radius",
                    undoName: "Change Streaming Upgrade Radius",
                    range: 0.5 ... 60.0,
                    help: "Textures closer than this distance stream to full resolution.",
                    get: { upgradeRadius },
                    set: { newValue in
                        upgradeRadius = newValue
                        TextureStreamingSystem.shared.upgradeRadius = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Downgrade Radius",
                    undoName: "Change Streaming Downgrade Radius",
                    range: 1.0 ... 120.0,
                    help: "Textures beyond this distance stream to the minimum dimension.",
                    get: { downgradeRadius },
                    set: { newValue in
                        downgradeRadius = newValue
                        TextureStreamingSystem.shared.downgradeRadius = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Max Texture Dimension",
                    undoName: "Change Max Texture Dimension",
                    range: 128 ... 4096,
                    format: "%.0f",
                    help: "Mid-distance max texture dimension, in pixels.",
                    get: { maxTextureDimension },
                    set: { newValue in
                        maxTextureDimension = newValue
                        TextureStreamingSystem.shared.maxTextureDimension = Int(newValue)
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Minimum Texture Dimension",
                    undoName: "Change Minimum Texture Dimension",
                    range: 32 ... 2048,
                    format: "%.0f",
                    help: "Far-distance max texture dimension, in pixels.",
                    get: { minimumTextureDimension },
                    set: { newValue in
                        minimumTextureDimension = newValue
                        TextureStreamingSystem.shared.minimumTextureDimension = Int(newValue)
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Hysteresis Fraction",
                    undoName: "Change Streaming Hysteresis",
                    range: 0.0 ... 0.5,
                    format: "%.2f",
                    help: "Dead-band fraction applied to each tier boundary to prevent oscillation near a radius.",
                    get: { hysteresisFraction },
                    set: { newValue in
                        hysteresisFraction = newValue
                        TextureStreamingSystem.shared.hysteresisFraction = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Max Concurrent Ops",
                    undoName: "Change Max Concurrent Streaming Ops",
                    range: 1 ... 12,
                    format: "%.0f",
                    help: "Maximum number of concurrent texture streaming operations.",
                    get: { maxConcurrentOps },
                    set: { newValue in
                        maxConcurrentOps = newValue
                        TextureStreamingSystem.shared.maxConcurrentOps = Int(newValue)
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )

                UndoableEffectSlider(
                    label: "Update Interval",
                    undoName: "Change Streaming Update Interval",
                    range: 0.02 ... 1.0,
                    format: "%.2f",
                    help: "How often to evaluate texture streaming, in seconds.",
                    get: { updateInterval },
                    set: { newValue in
                        updateInterval = newValue
                        TextureStreamingSystem.shared.updateInterval = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )
            }
        }
        .padding(.vertical, 4)
        .onAppear(perform: refreshFromEngine)
    }
}
