//
//  GaussianLODDistanceRow.swift
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

struct GaussianLODDistanceRow: View {
    let entityId: EntityID
    let lodIndex: Int
    let distance: Float
    let refreshView: () -> Void

    @State private var value: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("LOD\(lodIndex)")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            TextField("Distance", text: $value)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 72)
                .onAppear {
                    value = formattedDistance(distance)
                }
                .onChange(of: distance) { _, newDistance in
                    value = formattedDistance(newDistance)
                }
                .onSubmit {
                    commit()
                }
            Button(action: commit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 11))
                    .foregroundColor(.editorTextSecondary)
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Apply Gaussian LOD distance")
        }
    }

    private func commit() {
        guard let newDistance = Float(value) else {
            value = formattedDistance(distance)
            return
        }
        if updateEditorGaussianLODDistance(entityId: entityId, lodIndex: lodIndex, maxDistance: newDistance) {
            refreshView()
        }
    }

    private func formattedDistance(_ distance: Float) -> String {
        String(format: "%.2f", distance)
    }
}
