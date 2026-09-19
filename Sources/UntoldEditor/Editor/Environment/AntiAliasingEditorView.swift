//
//  AntiAliasingEditorView.swift
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
