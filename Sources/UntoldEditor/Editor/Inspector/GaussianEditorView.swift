//
//  GaussianEditorView.swift
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

struct GaussianEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gaussian Splats")

            HStack(spacing: 12) {
                Text(EditorGaussianAssetState.shared.metadata(for: entityId)?.sourceURL.deletingPathExtension().lastPathComponent ?? getAssetURLString(entityId: entityId) ?? " ")
                    .lineLimit(1)
                Button(action: {
                    let selectedCategory: AssetCategory = .gaussians
                    if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                        loadEditorGaussianAuto(entityId: entityId, url: assetPath) { success in
                            if success {
                                print("✅ Gaussian assigned: \(assetPath.lastPathComponent)")
                            } else {
                                print("⚠️ Failed to assign Gaussian: \(assetPath.lastPathComponent)")
                            }
                            refreshView()
                        }
                    } else {
                        refreshView()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.editorTextPrimary)
                        Text("Assign")
                            .fontWeight(.regular)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.editorSurface)
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.editorDivider, lineWidth: 1)
                    )
                    .shadow(color: Color.editorShadow, radius: 4, x: 0, y: 2)
                }
                .buttonStyle(PlainButtonStyle())
            }

            if let metadata = EditorGaussianAssetState.shared.metadata(for: entityId),
               let distances = metadata.progressiveMaxDistances
            {
                GaussianLoadingModeInspector(
                    entityId: entityId,
                    metadata: metadata,
                    refreshView: refreshView
                )
                GaussianProgressiveLODInspector(
                    entityId: entityId,
                    distances: distances,
                    refreshView: refreshView
                )
            } else if let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) {
                GaussianLoadingModeInspector(
                    entityId: entityId,
                    metadata: metadata,
                    refreshView: refreshView
                )
            }

            if let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) {
                GaussianRuntimeInspector(entityId: entityId, sourceURL: metadata.sourceURL)
            }
        }
        .padding(8)
        .background(Color.editorFillSubtle)
        .cornerRadius(8)
    }
}
