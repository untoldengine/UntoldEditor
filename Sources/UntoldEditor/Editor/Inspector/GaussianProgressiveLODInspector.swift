//
//  GaussianProgressiveLODInspector.swift
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

struct GaussianProgressiveLODInspector: View {
    let entityId: EntityID
    let distances: [Float]
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progressive LOD Distances")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)
                Spacer()
                Button(action: {
                    if resetEditorGaussianLODDistances(entityId: entityId) {
                        refreshView()
                    }
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.editorTextSecondary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Reset Gaussian LOD distances")
            }

            ForEach(Array(distances.enumerated()), id: \.offset) { index, distance in
                if index == distances.count - 1 {
                    HStack {
                        Text("LOD\(index)")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Text("Infinity")
                            .font(.system(size: 11))
                            .foregroundColor(.editorTextSecondary)
                    }
                } else {
                    GaussianLODDistanceRow(
                        entityId: entityId,
                        lodIndex: index,
                        distance: distance,
                        refreshView: refreshView
                    )
                }
            }
        }
        .padding(8)
        .background(Color.editorFill)
        .cornerRadius(6)
    }
}
