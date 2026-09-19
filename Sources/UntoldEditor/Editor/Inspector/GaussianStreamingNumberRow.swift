//
//  GaussianStreamingNumberRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

struct GaussianStreamingNumberRow: View {
    let label: String
    @Binding var value: String
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
            Spacer()
            TextField(label, text: $value)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 72)
                .onSubmit(onCommit)
            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.editorTextSecondary)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
    }
}
