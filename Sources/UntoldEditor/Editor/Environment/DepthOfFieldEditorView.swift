//
//  DepthOfFieldEditorView.swift
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
