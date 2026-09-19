//
//  LODLevelRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldEngine

struct LODLevelRow: View {
    let entityId: EntityID
    let lodIndex: Int
    let lodLevel: LODLevel
    let refreshView: () -> Void

    @State private var editingDistance: Bool = false
    @State private var distanceValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Top row: LOD badge and filename
            HStack(spacing: 8) {
                Text("LOD\(lodIndex)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.editorTextPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.editorInfo)
                    .cornerRadius(4)

                Text(lodLevel.url?.deletingPathExtension().lastPathComponent ?? "Unknown")
                    .font(.system(size: 11))
                    .foregroundColor(.editorTextPrimary)
                    .lineLimit(1)

                Spacer()
            }

            // Bottom row: Distance and remove button
            HStack(spacing: 8) {
                Text("Distance:")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)

                // Distance editor
                if editingDistance {
                    TextField("Distance", text: $distanceValue)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        .onSubmit {
                            if let newDistance = Float(distanceValue) {
                                updateLODDistance(newDistance: newDistance)
                            }
                            editingDistance = false
                        }
                } else {
                    Button(action: {
                        distanceValue = String(format: "%.0f", lodLevel.maxDistance)
                        editingDistance = true
                    }) {
                        Text(String(format: "%.0f", lodLevel.maxDistance))
                            .font(.system(size: 10))
                            .foregroundColor(.editorTextSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.editorFill)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Spacer()

                // Remove button
                Button(action: {
                    removeLODLevel(entityId: entityId, lodIndex: lodIndex)
                    refreshView()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.editorError)
                        .font(.system(size: 12))
                }
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(Color.editorFillSubtle)
        .cornerRadius(6)
    }

    private func updateLODDistance(newDistance: Float) {
        if let lodComponent = scene.get(component: LODComponent.self, for: entityId),
           lodIndex < lodComponent.lodLevels.count
        {
            lodComponent.lodLevels[lodIndex].maxDistance = newDistance
            refreshView()
        }
    }
}
