//
//  TransformVectorRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One row of the Transform section: a 56 pt label and the X, Y and Z fields.
struct TransformVectorRow: View {
    let label: String
    @Binding var value: SIMD3<Float>

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(EditorType.body)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 56, alignment: .leading)
            AxisNumberField(axis: .editorAxisX, value: $value.x)
            AxisNumberField(axis: .editorAxisY, value: $value.y)
            AxisNumberField(axis: .editorAxisZ, value: $value.z)
        }
    }
}
