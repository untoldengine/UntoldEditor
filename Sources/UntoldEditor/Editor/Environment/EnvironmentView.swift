//
//  EnvironmentView.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

@available(macOS 12.0, *)
struct EnvironmentView: View {
    @Binding var selectedAsset: Asset?
    var onLoadSceneAuthored: (Asset) -> Void = { _ in }

    private var selectedSceneAuthoredAsset: Asset? {
        guard let selectedAsset else {
            return nil
        }

        if let runtimeAsset = resolvedRuntimeAsset(for: selectedAsset),
           runtimeAsset.category == AssetCategory.models.rawValue,
           runtimeAssetExtensions(for: .models).contains(runtimeAsset.path.pathExtension.lowercased())
        {
            return runtimeAsset
        }

        if let manifestAsset = resolvedTiledSceneManifest(for: selectedAsset) {
            return manifestAsset
        }

        if selectedAsset.category == AssetCategory.streamModels.rawValue,
           selectedAsset.path.pathExtension.lowercased() == "remotestream"
        {
            return selectedAsset
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header

            HStack(spacing: 6) {
                Text("Environment Settings")
                    .font(.headline) // Smaller title
                    .foregroundColor(.editorTextPrimary)
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Scene Authored Data

            VStack(alignment: .leading, spacing: 6) {
                Text("Scene Authored")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)

                Button(action: loadSceneAuthoredFromSelection) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.badge.ellipsis")
                            .font(.system(size: 12))
                        Text("Load Scene Authored")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(selectedSceneAuthoredAsset == nil ? Color.editorSurface.opacity(0.45) : Color.editorAccent)
                    .foregroundColor(selectedSceneAuthoredAsset == nil ? .editorTextTertiary : .editorTextPrimary)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.editorDivider, lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(selectedSceneAuthoredAsset == nil)
                .help("Load Blender-authored cameras and lights from the selected .untold asset or tiled scene manifest")

                HStack {
                    Text("Source")
                        .foregroundColor(.editorTextSecondary)
                    Spacer()
                    Text(selectedSceneAuthoredAsset?.name ?? "None")
                        .foregroundColor(.editorTextTertiary)
                        .lineLimit(1)
                }
                .font(.system(size: 11))
            }

            Divider()

            // MARK: - Add IBL Button (Compact)

            Button(action: {
                addIBL(asset: selectedAsset)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.editorTextPrimary)
                        .font(.system(size: 12)) // Smaller icon
                    Text("Add IBL")
                        .font(.system(size: 12))
                        .fontWeight(.semibold)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.editorSurface)
                .foregroundColor(.editorTextPrimary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            Divider()

            // MARK: - IBL and Environment Toggles (Compact)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Apply IBL", systemImage: applyIBL ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { applyIBL },
                        set: { newValue in
                            applyIBL = newValue
                            EditorSceneDirtyState.shared.markDirty()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.editorAccent)
                }

                HStack {
                    Label("Render Environment", systemImage: renderEnvironment ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { renderEnvironment },
                        set: { newValue in
                            renderEnvironment = newValue
                            EditorSceneDirtyState.shared.markDirty()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.editorAccent)
                }

                HStack {
                    Label(renderSkyBackground ? "Sky Background" : "Grid Background", systemImage: renderSkyBackground ? "sun.max.fill" : "square.grid.3x3")
                        .font(.system(size: 12))
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { renderSkyBackground },
                        set: { newValue in
                            renderSkyBackground = newValue
                            EditorSceneDirtyState.shared.markDirty()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Color.editorAccent)
                }
                .help("Switch the non-IBL background between the procedural sky and the debug/editor grid")
            }

            Divider()

            // MARK: - Color LUT Toggle (Compact)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: Binding(
                    get: { ColorLUTParams.shared.enabled },
                    set: { newValue in
                        ColorLUTParams.shared.enabled = newValue
                        EditorSceneDirtyState.shared.markDirty()
                    }
                )) {
                    Label("Apply Color LUT", systemImage: ColorLUTParams.shared.enabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.85)

                Text("Compares the baked Blender color-grading LUT against the default tonemap. Only takes effect if the loaded asset has a baked LUT.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Divider()

            // MARK: - Ambient Intensity Slider (Compact)

            VStack(alignment: .leading, spacing: 4) {
                Text("Ambient Intensity")
                    .font(.system(size: 12))
                    .foregroundColor(.editorTextPrimary)

                TextInputNumberView(label: "Intensity", value: Binding(
                    get: { ambientIntensity },
                    set: { newIntensity in
                        ambientIntensity = newIntensity
                        EditorSceneDirtyState.shared.markDirty()
                    }
                ))
                .frame(maxWidth: 80) // Make the input field smaller
            }
        }
    }

    private func resolvedRuntimeAsset(for asset: Asset) -> Asset? {
        guard asset.isFolder else { return asset }
        guard asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue else {
            return nil
        }
        guard let category = AssetCategory(rawValue: asset.category),
              let runtimeAssetURL = primaryRuntimeAsset(in: asset.path, allowedExtensions: runtimeAssetExtensions(for: category))
        else {
            return nil
        }

        return Asset(
            name: runtimeAssetURL.lastPathComponent,
            category: asset.category,
            path: runtimeAssetURL,
            isFolder: false
        )
    }

    private func resolvedTiledSceneManifest(for asset: Asset) -> Asset? {
        guard asset.category == AssetCategory.streamModels.rawValue else {
            return nil
        }

        if asset.isFolder {
            guard let manifestURL = primaryTiledSceneManifest(in: asset.path) else {
                return nil
            }

            return Asset(
                name: manifestURL.lastPathComponent,
                category: asset.category,
                path: manifestURL,
                isFolder: false
            )
        }

        guard isTiledSceneManifest(asset.path) else {
            return nil
        }

        return asset
    }

    private func loadSceneAuthoredFromSelection() {
        guard let asset = selectedSceneAuthoredAsset else {
            return
        }

        onLoadSceneAuthored(asset)
    }
}
