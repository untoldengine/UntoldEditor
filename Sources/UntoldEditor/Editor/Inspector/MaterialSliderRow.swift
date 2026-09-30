//
//  MaterialSliderRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One material slider: its label, the slider and the value in mono.
struct MaterialSliderRow: View {
    let label: String
    @Binding var value: Float
    var range: ClosedRange<Float> = 0 ... 1
    var isEnabled = true

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 64, alignment: .leading)
            EditorSlider(value: $value, range: range, isEnabled: isEnabled)
            Text(String(format: "%.2f", value))
                .font(EditorType.mono)
                .foregroundColor(.editorTextPrimary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}
