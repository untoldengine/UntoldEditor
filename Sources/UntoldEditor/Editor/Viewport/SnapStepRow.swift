//
//  SnapStepRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One kind of snapping in the snap menu: its switch, its name and its steps.
struct SnapStepRow: View {
    let title: String
    @Binding var isOn: Bool
    @Binding var step: Float
    let steps: [Float]
    let label: (Float) -> String

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.editorAccent)
                .controlSize(.small)
            Text(title)
                .font(EditorType.body)
                .foregroundColor(.editorTextPrimary)
                .frame(width: 48, alignment: .leading)
            EditorSegmented(options: steps, selection: $step, label: label)
                .disabled(isOn == false)
                .opacity(isOn ? 1 : 0.6)
        }
    }
}
