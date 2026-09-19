//
//  PostProcessingEditorView.swift
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

struct PostProcessingEditorView: View {
    @Binding var selectedAsset: Asset?

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
    @State private var showColorGradeLUT = false
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

                DisclosureGroup("Color Grade LUT", isExpanded: $showColorGradeLUT) {
                    ColorGradeLUTEditorView(selectedAsset: $selectedAsset)
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
