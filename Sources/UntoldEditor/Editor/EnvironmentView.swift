//
//  EnvironmentView.swift
//
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

func addIBL(asset: Asset?) {
    let selectedCategory: AssetCategory = .hdr

    if let asset, selectedCategory.rawValue == asset.category {
        let filename = asset.path.lastPathComponent
        let directoryURL = asset.path.deletingLastPathComponent()

        // Verify HDR file exists before attempting to load
        let hdrPath = directoryURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: hdrPath.path) else {
            Logger.log(message: "⚠️ HDR file not found: \(hdrPath.path)")
            return
        }

        generateHDR(filename, from: directoryURL)

        // Only enable IBL if HDR was successfully loaded
        if iblSuccessful {
            applyIBL = true
            Logger.log(message: "✅ IBL enabled with HDR: \(filename)")
        } else {
            Logger.log(message: "⚠️ Failed to enable IBL - HDR loading failed")
        }
    }
}

@available(macOS 12.0, *)
struct EnvironmentView: View {
    @State private var enableApplyIBL: Bool = false
    @State private var enableRenderEnvironment: Bool = false
    @State private var enableColorLUT: Bool = false
    @State private var intensity: Float = 1.0
    @Binding var selectedAsset: Asset?
    var onLoadSceneAuthored: (Asset) -> Void = { _ in }

    private var selectedSceneAuthoredAsset: Asset? {
        guard let selectedAsset else {
            return nil
        }

        if let runtimeAsset = resolvedRuntimeAsset(for: selectedAsset),
           runtimeAsset.category == AssetCategory.models.rawValue,
           runtimeAsset.path.pathExtension.lowercased() == "untold"
        {
            return runtimeAsset
        }

        if let manifestAsset = resolvedTiledSceneManifest(for: selectedAsset) {
            return manifestAsset
        }

        if selectedAsset.category == AssetCategory.streamModels.rawValue,
           selectedAsset.path.pathExtension.lowercased() == "remotestream"
        {
            return selectedAsset
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header

            HStack(spacing: 6) {
                Text("Environment Settings")
                    .font(.headline) // Smaller title
                    .foregroundColor(.editorTextPrimary)
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Scene Authored Data

            VStack(alignment: .leading, spacing: 6) {
                Text("Scene Authored")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)

                Button(action: loadSceneAuthoredFromSelection) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 12))
                        Text("Load Scene Authored")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedSceneAuthoredAsset == nil ? Color.editorSurface.opacity(0.45) : Color.editorAccent)
                    .foregroundColor(selectedSceneAuthoredAsset == nil ? .editorTextTertiary : .editorTextPrimary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.editorDivider, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedSceneAuthoredAsset == nil)
                .help("Load Blender-authored cameras and lights from the selected .untold asset or tiled scene manifest")

                HStack {
                    Text("Source")
                        .foregroundColor(.editorTextSecondary)
                    Spacer()
                    Text(selectedSceneAuthoredAsset?.name ?? "None")
                        .foregroundColor(.editorTextTertiary)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
            }

            Divider()

            // MARK: - Add IBL Button (Compact)

            Button(action: {
                addIBL(asset: selectedAsset)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.editorTextPrimary)
                        .font(.system(size: 12)) // Smaller icon
                    Text("Add IBL")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.editorSurface)
                .foregroundColor(.editorTextPrimary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Divider()

            // MARK: - IBL and Environment Toggles (Compact)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Apply IBL", systemImage: enableApplyIBL ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: $enableApplyIBL)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Color.editorAccent)
                }
                .onChange(of: enableApplyIBL) { _, newValue in
                    applyIBL = newValue
                }

                HStack {
                    Label("Render Environment", systemImage: enableRenderEnvironment ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: $enableRenderEnvironment)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Color.editorAccent)
                }
                .onChange(of: enableRenderEnvironment) { _, newValue in
                    renderEnvironment = newValue
                }
            }

            Divider()

            // MARK: - Color LUT Toggle (Compact)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $enableColorLUT) {
                    Label("Apply Color LUT", systemImage: enableColorLUT ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.85)
                .onChange(of: enableColorLUT) { _, newValue in
                    ColorLUTParams.shared.enabled = newValue
                    enableColorLUT = ColorLUTParams.shared.enabled
                }

                Text("Compares the baked Blender color-grading LUT against the default tonemap. Only takes effect if the loaded asset has a baked LUT.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            // MARK: - Ambient Intensity Slider (Compact)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ambient Intensity")
                    .font(.system(size: 12))
                    .foregroundColor(.editorTextPrimary)

                TextInputNumberView(label: "Intensity", value: Binding(
                    get: { intensity },
                    set: { newIntensity in
                        ambientIntensity = newIntensity
                        intensity = newIntensity
                    }
                ))
                .frame(maxWidth: 80) // Make the input field smaller
            }
        }
        .onAppear {
            enableApplyIBL = applyIBL
            enableRenderEnvironment = renderEnvironment
            enableColorLUT = ColorLUTParams.shared.enabled
            intensity = ambientIntensity
        }
    }

    private func resolvedRuntimeAsset(for asset: Asset) -> Asset? {
        guard asset.isFolder else { return asset }
        guard asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue else {
            return nil
        }
        guard let runtimeAssetURL = primaryRuntimeAsset(in: asset.path) else {
            return nil
        }

        return Asset(
            name: runtimeAssetURL.lastPathComponent,
            category: asset.category,
            path: runtimeAssetURL,
            isFolder: false
        )
    }

    private func resolvedTiledSceneManifest(for asset: Asset) -> Asset? {
        guard asset.category == AssetCategory.streamModels.rawValue else {
            return nil
        }

        if asset.isFolder {
            guard let manifestURL = primaryTiledSceneManifest(in: asset.path) else {
                return nil
            }

            return Asset(
                name: manifestURL.lastPathComponent,
                category: asset.category,
                path: manifestURL,
                isFolder: false
            )
        }

        guard isTiledSceneManifest(asset.path) else {
            return nil
        }

        return asset
    }

    private func loadSceneAuthoredFromSelection() {
        guard let asset = selectedSceneAuthoredAsset else {
            return
        }

        onLoadSceneAuthored(asset)
    }
}

private struct UndoableEffectToggle<Label: View>: View {
    let undoName: String
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack {
            label()
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    let oldValue = isOn
                    isOn = newValue
                    DispatchQueue.main.async {
                        EditorUndoManager.shared.registerValueChange(
                            name: undoName,
                            oldValue: oldValue,
                            newValue: newValue,
                            apply: { isOn = $0 }
                        )
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color.editorAccent)
        }
    }
}

private struct UndoableEffectSlider: View {
    let label: String
    let undoName: String
    let range: ClosedRange<Float>
    var format: String = "%.2f"
    let get: () -> Float
    let set: (Float) -> Void

    @State private var editStartValue: Float?

    var body: some View {
        Text(label)
        Slider(
            value: Binding(
                get: get,
                set: set
            ),
            in: range,
            onEditingChanged: { isEditing in
                if isEditing {
                    editStartValue = get()
                } else if let oldValue = editStartValue {
                    let newValue = get()
                    EditorUndoManager.shared.registerValueChange(
                        name: undoName,
                        oldValue: oldValue,
                        newValue: newValue,
                        apply: set
                    )
                    editStartValue = nil
                }
            }
        )
        .tint(Color.editorAccent)
        Text(String(format: format, get()))
    }
}

struct ColorGradingEditorView: View {
    @ObservedObject var settings = ColorGradingParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Color Grading",
                isOn: $settings.enabled
            ) {
                Text("Enable Color Grading")
            }

            UndoableEffectSlider(label: "Exposure", undoName: "Change Exposure", range: -5.0 ... 5.0, get: { settings.exposure }, set: { settings.exposure = $0 })
            UndoableEffectSlider(label: "Brightness", undoName: "Change Brightness", range: -1.0 ... 1.0, get: { settings.brightness }, set: { settings.brightness = $0 })
            UndoableEffectSlider(label: "Contrast", undoName: "Change Contrast", range: -5.0 ... 5.0, get: { settings.contrast }, set: { settings.contrast = $0 })
            UndoableEffectSlider(label: "Saturation", undoName: "Change Saturation", range: 0.0 ... 5.0, get: { settings.saturation }, set: { settings.saturation = $0 })
        }
        .padding(.vertical, 4)
    }
}

struct WhiteBalanceEditorView: View {
    @ObservedObject var settings = ColorGradingParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectSlider(label: "Temperature", undoName: "Change Temperature", range: -100.0 ... 100.0, get: { settings.temperature }, set: { settings.temperature = $0 })
            UndoableEffectSlider(label: "Tint", undoName: "Change Tint", range: -100.0 ... 100.0, get: { settings.tint }, set: { settings.tint = $0 })

//            TextInputVectorView(label: "Lift", value: Binding(
//                get: { settings.lift },
//                set: { newLift in
//                    settings.lift = newLift
//                }))
//
//            TextInputVectorView(label: "Gamma", value: Binding(
//                get: { settings.gamma },
//                set: { newGamma in
//                    settings.gamma = newGamma
//                }))
//
//            TextInputVectorView(label: "Gain", value: Binding(
//                get: { settings.gain },
//                set: { newGain in
//                    settings.gain = newGain
//                }))
        }
        .padding(.vertical, 4)
    }
}

struct BloomEditorView: View {
    @ObservedObject var settings = BloomThresholdParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Bloom",
                isOn: $settings.enabled
            ) {
                Text("Enable Bloom")
            }

            UndoableEffectSlider(label: "Threshold", undoName: "Change Bloom Threshold", range: 0.0 ... 5.0, get: { settings.threshold }, set: { settings.threshold = $0 })
            UndoableEffectSlider(label: "Intensity", undoName: "Change Bloom Intensity", range: 0.0 ... 100.0, get: { settings.intensity }, set: { settings.intensity = $0 })
        }
        .padding(.vertical, 4)
    }
}

struct VignetteEditorView: View {
    @ObservedObject var settings = VignetteParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Vignette",
                isOn: $settings.enabled
            ) {
                Text("Enable Vignette")
            }

            UndoableEffectSlider(label: "Intensity", undoName: "Change Vignette Intensity", range: 0.0 ... 1.0, get: { settings.intensity }, set: { settings.intensity = $0 })
            UndoableEffectSlider(label: "Radius", undoName: "Change Vignette Radius", range: 0.0 ... 1.0, get: { settings.radius }, set: { settings.radius = $0 })
            UndoableEffectSlider(label: "Softness", undoName: "Change Vignette Softness", range: 0.0 ... 1.0, get: { settings.softness }, set: { settings.softness = $0 })

//            TextInputVectorView(label: "Center", value: Binding(
//                get: { settings.center },
//                set: { newCenter in
//                    settings.center = newCenter
//                }))
        }
        .padding(.vertical, 4)
    }
}

struct ChromaticAberrationEditorView: View {
    @ObservedObject var settings = ChromaticAberrationParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Chromatic Aberration",
                isOn: $settings.enabled
            ) {
                Text("Enable Chromatic Aberration")
            }

            UndoableEffectSlider(label: "Intensity", undoName: "Change Chromatic Aberration Intensity", range: 0.0 ... 0.01, format: "%.4f", get: { settings.intensity }, set: { settings.intensity = $0 })

//            TextInputVectorView(label: "Center", value: Binding(
//                get: { settings.center },
//                set: { newCenter in
//                    settings.center = newCenter
//                }))
        }
        .padding(.vertical, 4)
    }
}

struct DepthOfFieldEditorView: View {
    @ObservedObject var settings = DepthOfFieldParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle Depth of Field",
                isOn: $settings.enabled
            ) {
                Text("Enable Depth of Field")
            }

            UndoableEffectSlider(label: "Focus Distance", undoName: "Change Focus Distance", range: 0.0 ... 10.0, get: { settings.focusDistance }, set: { settings.focusDistance = $0 })
            UndoableEffectSlider(label: "Focus Range", undoName: "Change Focus Range", range: 0.0 ... 10.0, format: "%.4f", get: { settings.focusRange }, set: { settings.focusRange = $0 })
            UndoableEffectSlider(label: "Max Blur", undoName: "Change Max Blur", range: 0.0 ... 0.05, format: "%.4f", get: { settings.maxBlur }, set: { settings.maxBlur = $0 })
        }
        .padding(.vertical, 4)
    }
}

struct SSAOEditorView: View {
    @ObservedObject var settings = SSAOParams.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UndoableEffectToggle(
                undoName: "Toggle SSAO",
                isOn: $settings.enabled
            ) {
                Text("Enable SSAO")
            }

            UndoableEffectSlider(label: "Radius", undoName: "Change SSAO Radius", range: 0.1 ... 1.0, get: { settings.radius }, set: { settings.radius = $0 })
            UndoableEffectSlider(label: "Bias", undoName: "Change SSAO Bias", range: 0.0 ... 0.1, format: "%.4f", get: { settings.bias }, set: { settings.bias = $0 })
            UndoableEffectSlider(label: "Intensity", undoName: "Change SSAO Intensity", range: 0.0 ... 2.0, get: { settings.intensity }, set: { settings.intensity = $0 })
        }
        .padding(.vertical, 4)
    }
}

private enum EditorAntiAliasingOption: String, CaseIterable, Hashable, Identifiable {
    case off = "Off"
    case fxaa = "FXAA"
    case smaa = "SMAA"
    case msaa = "MSAA"

    var id: String {
        rawValue
    }

    var engineMode: AntiAliasingMode {
        switch self {
        case .off:
            return .none
        case .fxaa:
            return .fxaa
        case .smaa:
            return .smaa
        case .msaa:
            return .msaa
        }
    }

    static func currentEngineMode() -> EditorAntiAliasingOption {
        switch antiAliasingMode {
        case .none:
            return .off
        case .fxaa:
            return .fxaa
        case .smaa:
            return .smaa
        case .msaa:
            return .msaa
        }
    }
}

struct AntiAliasingEditorView: View {
    @ObservedObject var fxaaSettings = FXAAParams.shared
    @ObservedObject var smaaSettings = SMAAParams.shared
    @State private var selectedMode = EditorAntiAliasingOption.currentEngineMode()
    @State private var showAdvanced = false

    private func selectMode(_ newValue: EditorAntiAliasingOption) {
        let oldValue = selectedMode
        guard oldValue != newValue else { return }
        selectedMode = newValue
        antiAliasingMode = newValue.engineMode
        EditorUndoManager.shared.registerValueChange(
            name: "Change Anti-Aliasing",
            oldValue: oldValue,
            newValue: newValue,
            apply: { option in
                antiAliasingMode = option.engineMode
                selectedMode = option
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Themed segmented control (equal-width segments that adapt to the
            // panel width — unlike a native .segmented picker, which has a large
            // intrinsic minimum width and would push the panel out of alignment).
            HStack(spacing: 2) {
                ForEach(EditorAntiAliasingOption.allCases) { option in
                    let isSelected = selectedMode == option
                    Button(action: { selectMode(option) }) {
                        Text(option.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .foregroundColor(isSelected ? .editorTextPrimary : .editorTextSecondary)
                            .background(isSelected ? Color.editorAccent : Color.clear)
                            .cornerRadius(5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                }
            }
            .padding(3)
            .frame(maxWidth: .infinity)
            .background(Color.editorSurface.opacity(0.6))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.editorDivider, lineWidth: 1)
            )

            switch selectedMode {
            case .off:
                EmptyView()
            case .fxaa:
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        UndoableEffectSlider(
                            label: "Subpixel Quality",
                            undoName: "Change FXAA Subpixel Quality",
                            range: 0.0 ... 1.0,
                            get: { fxaaSettings.subpixelQuality },
                            set: { fxaaSettings.subpixelQuality = $0 }
                        )
                        UndoableEffectSlider(
                            label: "Edge Threshold",
                            undoName: "Change FXAA Edge Threshold",
                            range: 0.0312 ... 0.3333,
                            format: "%.4f",
                            get: { fxaaSettings.edgeThreshold },
                            set: { fxaaSettings.edgeThreshold = $0 }
                        )
                        UndoableEffectSlider(
                            label: "Minimum Edge Threshold",
                            undoName: "Change FXAA Minimum Edge Threshold",
                            range: 0.0 ... 0.125,
                            format: "%.4f",
                            get: { fxaaSettings.edgeThresholdMin },
                            set: { fxaaSettings.edgeThresholdMin = $0 }
                        )
                    }
                    .padding(.top, 4)
                }
            case .smaa:
                DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                    VStack(alignment: .leading, spacing: 8) {
                        UndoableEffectSlider(
                            label: "Edge Threshold",
                            undoName: "Change SMAA Edge Threshold",
                            range: 0.01 ... 0.5,
                            format: "%.4f",
                            get: { smaaSettings.edgeThreshold },
                            set: { smaaSettings.edgeThreshold = $0 }
                        )
                    }
                    .padding(.top, 4)
                }
            case .msaa:
                EmptyView()
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            selectedMode = EditorAntiAliasingOption.currentEngineMode()
        }
    }
}

private enum EditorTonemapOption: String, CaseIterable, Hashable, Identifiable {
    case agx = "AgX"
    case aces = "ACES"

    var id: String {
        rawValue
    }

    var engineOperator: TonemapOperator {
        switch self {
        case .agx:
            return .agx
        case .aces:
            return .aces
        }
    }

    static func currentEngineOperator() -> EditorTonemapOption {
        switch TonemapParams.shared.operator {
        case .agx:
            return .agx
        case .aces:
            return .aces
        }
    }
}

struct ToneMappingEditorView: View {
    @State private var selectedOperator = EditorTonemapOption.currentEngineOperator()

    private func selectOperator(_ newValue: EditorTonemapOption) {
        let oldValue = selectedOperator
        guard oldValue != newValue else { return }

        let before = EditorPostFXSnapshot()
        selectedOperator = newValue
        setPostFX(.tonemapOperator(newValue.engineOperator))
        EditorUndoManager.shared.registerPostFXChange(
            name: "Change Tonemap Operator",
            before: before,
            after: EditorPostFXSnapshot()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Operator", selection: Binding(
                get: { selectedOperator },
                set: selectOperator
            )) {
                ForEach(EditorTonemapOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .onAppear {
            selectedOperator = EditorTonemapOption.currentEngineOperator()
        }
    }
}

struct PostProcessingEditorView: View {
    private enum PresetOption: String, CaseIterable, Identifiable {
        case neutral = "Neutral"
        case cinematic = "Cinematic"
        case highContrast = "High Contrast"
        case softAO = "Soft AO"
        case archviz = "Archviz"

        var id: String {
            rawValue
        }

        var enginePreset: PostFXPreset {
            switch self {
            case .neutral: return .neutral
            case .cinematic: return .cinematic
            case .highContrast: return .highContrast
            case .softAO: return .softAO
            case .archviz: return .archviz
            }
        }
    }

    @State private var showPresets = true
    @State private var selectedPreset: PresetOption = .neutral
    @State private var showAntiAliasing = false
    @State private var showToneMapping = false
    @State private var showWhiteBalance = false
    @State private var showColorGrading = false
    @State private var showBloom = false
    @State private var showVignette = false
    @State private var showChromatic = false
    @State private var showDoF = false
    @State private var showSSAO = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DisclosureGroup("Presets", isExpanded: $showPresets) {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Preset", selection: $selectedPreset) {
                            ForEach(PresetOption.allCases) { preset in
                                Text(preset.rawValue).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: selectedPreset) { _, newValue in
                            let before = EditorPostFXSnapshot()
                            PostFX.apply(newValue.enginePreset)
                            EditorUndoManager.shared.registerPostFXChange(
                                name: "Apply \(newValue.rawValue) Preset",
                                before: before,
                                after: EditorPostFXSnapshot()
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }

                DisclosureGroup("Anti-Aliasing", isExpanded: $showAntiAliasing) {
                    AntiAliasingEditorView()
                }

                DisclosureGroup("Tone Mapping", isExpanded: $showToneMapping) {
                    ToneMappingEditorView()
                }

                DisclosureGroup("Depth of Field", isExpanded: $showDoF) {
                    DepthOfFieldEditorView()
                }

                DisclosureGroup("Chromatic Aberration", isExpanded: $showChromatic) {
                    ChromaticAberrationEditorView()
                }

                DisclosureGroup("Bloom", isExpanded: $showBloom) {
                    BloomEditorView()
                }

                DisclosureGroup("Color Grading", isExpanded: $showColorGrading) {
                    ColorGradingEditorView()
                }

                DisclosureGroup("WhiteBalance", isExpanded: $showWhiteBalance) {
                    WhiteBalanceEditorView()
                }

                DisclosureGroup("Vignette", isExpanded: $showVignette) {
                    VignetteEditorView()
                }

                DisclosureGroup("SSAO", isExpanded: $showSSAO) {
                    SSAOEditorView()
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disclosureGroupStyle(EditorDisclosureStyle())
    }
}
