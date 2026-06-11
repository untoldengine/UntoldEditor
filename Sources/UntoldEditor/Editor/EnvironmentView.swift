//
//  EnvironmentView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
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
    @State private var intensity: Float = 1.0
    @Binding var selectedAsset: Asset?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header

            HStack(spacing: 6) {
                Image(systemName: "leaf.arrow.triangle.circlepath")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14)) // Smaller icon
                Text("Environment Settings")
                    .font(.headline) // Smaller title
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Add IBL Button (Compact)

            Button(action: {
                addIBL(asset: selectedAsset)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 12)) // Smaller icon
                    Text("Add IBL")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.editorAccent)
                .foregroundColor(.white)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())

            Divider()

            // MARK: - IBL and Environment Toggles (Compact)

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $enableApplyIBL) {
                    Label("Apply IBL", systemImage: enableApplyIBL ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.85) // Make toggle smaller
                .onChange(of: enableApplyIBL) { _, newValue in
                    applyIBL = newValue
                }

                Toggle(isOn: $enableRenderEnvironment) {
                    Label("Render Environment", systemImage: enableRenderEnvironment ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.85)
                .onChange(of: enableRenderEnvironment) { _, newValue in
                    renderEnvironment = newValue
                }
            }

            Divider()

            // MARK: - Ambient Intensity Slider (Compact)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ambient Intensity")
                    .font(.system(size: 12))
                    .foregroundColor(.primary)

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
        .padding(8) // Reduce padding
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
        .onAppear {
            enableApplyIBL = applyIBL
            enableRenderEnvironment = renderEnvironment
            intensity = ambientIntensity
        }
    }
}

private struct UndoableEffectToggle<Label: View>: View {
    let undoName: String
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        Toggle(isOn: Binding(
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
        ), label: label)
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
        .padding()
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
        .padding()
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
        .padding()
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
        .padding()
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
        .padding()
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
        .padding()
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
        .padding()
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $selectedMode) {
                ForEach(EditorAntiAliasingOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedMode) { oldValue, newValue in
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
        .padding()
        .onAppear {
            selectedMode = EditorAntiAliasingOption.currentEngineMode()
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
                    .padding()
                }

                DisclosureGroup("Anti-Aliasing", isExpanded: $showAntiAliasing) {
                    AntiAliasingEditorView()
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
            .padding()
        }
    }
}
