//
//  LODComponentEditorView.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

struct LODComponentEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "square.3.layers.3d")
                    .foregroundColor(.editorInfo)
                Text("LOD Levels")
                    .font(.headline)
            }

            if let lodComponent = scene.get(component: LODComponent.self, for: entityId) {
                // Show existing LOD levels
                ForEach(Array(lodComponent.lodLevels.enumerated()), id: \.offset) { index, lodLevel in
                    LODLevelRow(
                        entityId: entityId,
                        lodIndex: index,
                        lodLevel: lodLevel,
                        refreshView: refreshView
                    )
                }

                // Add LOD Level button
                Button(action: {
                    addLODLevelFromFilePicker()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.editorTextPrimary)
                        Text("Add LOD Level")
                            .fontWeight(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorSuccess)
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 8)
            }
        }
        .padding(12)
        .background(Color.editorInfo.opacity(0.05))
        .cornerRadius(8)
    }

    private func addLODLevelFromFilePicker() {
        // Check if user has selected a model asset
        guard let asset,
              asset.category == "Models",
              !asset.isFolder
        else {
            Logger.log(message: "⚠️ Please select a .untold file from the Models section first")
            return
        }

        let url = asset.path
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        // Get the next LOD index
        if let lodComponent = scene.get(component: LODComponent.self, for: entityId) {
            let lodIndex = lodComponent.lodLevels.count

            // Default distance based on index: 50, 100, 150, 200, etc.
            let maxDistance = Float((lodIndex + 1) * 50)

            // Add LOD level
            addLODLevel(
                entityId: entityId,
                lodIndex: lodIndex,
                fileName: filename,
                withExtension: ext,
                maxDistance: maxDistance
            ) { success in
                if success {
                    Logger.log(message: "✅ Added LOD level \(lodIndex): \(filename)")
                    refreshView()
                } else {
                    Logger.log(message: "⚠️ Failed to add LOD level \(lodIndex)")
                }
            }
        }
    }
}

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
