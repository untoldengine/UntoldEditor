//
//  ReadOnlyVectorView.swift
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

struct ReadOnlyVectorView: View {
    let label: String
    let value: simd_float3

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.headline)

            HStack {
                vectorValue(value.x)
                vectorValue(value.y)
                vectorValue(value.z)
            }
        }
        .padding(.vertical, 4)
    }

    private func vectorValue(_ value: Float) -> some View {
        Text(value, format: .number.precision(.fractionLength(3)))
            .frame(width: 60)
            .padding(.vertical, 3)
            .background(Color.editorFill)
            .cornerRadius(4)
    }
}
