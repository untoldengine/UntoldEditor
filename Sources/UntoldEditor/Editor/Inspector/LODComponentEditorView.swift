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
