//
//  RenderingEditorView.swift
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

private func pickTextureImageFile() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [.png, .jpeg, .tiff]

    return panel.runModal() == .OK ? panel.urls.first : nil
}

/// Copies an externally-picked texture image into the project's Materials asset folder,
/// mirroring the single-file fallback of the Asset Browser's own Materials import (a
/// subfolder named after the file, matching what updateMaterialTexture(path:) expects to
/// resolve via LoadingSystem's resource search paths).
private func importTextureAsset(from sourceURL: URL) -> URL? {
    guard let basePath = assetBasePath else {
        Logger.logWarning(message: "[InspectorView] assetBasePath is not set; cannot import texture \(sourceURL.lastPathComponent).")
        return nil
    }

    let fm = FileManager.default
    let materialsRoot = basePath.appendingPathComponent("Materials", isDirectory: true)
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let materialFolder = materialsRoot.appendingPathComponent(baseName, isDirectory: true)
    let destFile = materialFolder.appendingPathComponent(sourceURL.lastPathComponent)

    do {
        try fm.createDirectory(at: materialFolder, withIntermediateDirectories: true)
        if fm.fileExists(atPath: destFile.path) {
            try fm.removeItem(at: destFile)
        }
        try fm.copyItem(at: sourceURL, to: destFile)
        return destFile
    } catch {
        Logger.logWarning(message: "[InspectorView] Failed to import texture \(sourceURL.lastPathComponent): \(error.localizedDescription)")
        return nil
    }
}

private func onAddMesh_Editor(entityId: EntityID, url: URL) {
    let filename = url.deletingPathExtension().lastPathComponent
    let withExtension = url.pathExtension

    setEntityMeshAsync(entityId: entityId, filename: filename, withExtension: withExtension) { success in
        if success {
            print("✅ Mesh loaded: \(filename).\(withExtension)")
        } else {
            print("⚠️ Failed to load mesh, using fallback: \(filename).\(withExtension)")
        }
    }
}

struct RenderingEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void
    var meshIndex: Int = 0
    var inspectionOnly: Bool = false
    @State private var hasPendingUntoldWrite = false
    @State private var untoldUpdateStatus: String?

    var body: some View {
        let readOnlyRender = EditorAuthoringMode.sceneCompositionOnly || inspectionOnly

        return VStack(alignment: .leading) {
            Text("Mesh")

            HStack(spacing: 12) {
                Text(meshLabel)

                if readOnlyRender == false {
                    Button(action: {
                        let selectedCategory: AssetCategory = .models
                        if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                            onAddMesh_Editor(entityId: entityId, url: assetPath)
                        }
                        refreshView()
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
            }
            .padding(8)
            .background(Color.editorFillSubtle)
            .cornerRadius(8)

            if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
                Toggle(isOn: Binding(
                    get: { getEntityCastsShadow(entityId: entityId) },
                    set: { enabled in
                        setEntityCastsShadow(entityId: entityId, enabled)
                        EditorSceneDirtyState.shared.markDirty()
                        refreshView()
                    }
                )) {
                    Text("Cast Shadows")
                }
                .toggleStyle(.checkbox)
                .disabled(inspectionOnly)
                .opacity(inspectionOnly ? 0.7 : 1.0)
            }

            if hasComponent(entityId: entityId, componentType: RenderComponent.self),
               hasComponent(entityId: entityId, componentType: LightComponent.self) == false
            {
                Text("Material Properties")
                    .font(.headline)
                    .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(TextureType.allCases) { type in
                            let textureURL = getMaterialTextureURL(entityId: entityId, type: type, meshIndex: meshIndex)
                            let hoverText = editorMaterialSlotHoverText(textureType: type, textureURL: textureURL)
                            let image: NSImage? = {
                                if let img = getMaterialTextureImage(entityId: entityId, type: type, meshIndex: meshIndex) {
                                    return img
                                } else {
                                    return NSImage(named: "Default Texture")
                                }
                            }()

                            VStack(alignment: .center, spacing: 8) {
                                Button(action: {
                                    if asset?.category == "Materials", let path = asset?.path {
                                        updateMaterialTexture(entityId: entityId, textureType: type, path: path, meshIndex: meshIndex)
                                        EditorSceneDirtyState.shared.markDirty()
                                        refreshView()
                                    } else if let pickedURL = pickTextureImageFile(),
                                              let importedURL = importTextureAsset(from: pickedURL)
                                    {
                                        updateMaterialTexture(entityId: entityId, textureType: type, path: importedURL, meshIndex: meshIndex)
                                        EditorSceneDirtyState.shared.markDirty()
                                        refreshView()
                                    }
                                }) {
                                    if let image {
                                        Image(nsImage: image)
                                            .resizable()
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(6)
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .frame(width: 64, height: 64)
                                            .foregroundColor(.editorTextTertiary)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(hoverText)

                                HStack(spacing: 8) {
                                    Button(action: {
                                        removeMaterialTexture(entityId: entityId, textureType: type, meshIndex: meshIndex)
                                        EditorSceneDirtyState.shared.markDirty()
                                        refreshView()
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.editorError)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())

                                    if canRestoreEmbeddedTexture(entityId: entityId, type: type, meshIndex: meshIndex) {
                                        Button(action: {
                                            restoreEmbeddedTexture(entityId: entityId, textureType: type, meshIndex: meshIndex)
                                            EditorSceneDirtyState.shared.markDirty()
                                            refreshView()
                                        }) {
                                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                                .foregroundColor(.editorInfo)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .help("Restore original embedded texture")
                                    }
                                }
                                .disabled(inspectionOnly)
                                .opacity(inspectionOnly ? 0.7 : 1.0)

                                Text(type.displayName)
                                    .font(.caption)
                                    .padding(.top, 4)

                                Divider().padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Wrap Mode")
                                        .font(.caption)
                                        .foregroundColor(.editorTextSecondary)

                                    Picker("", selection: bindingForWrapMode(entityId: entityId, textureType: type, meshIndex: meshIndex, onChange: refreshView)) {
                                        ForEach(WrapMode.allCases) { mode in
                                            Text(mode.description).tag(mode)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: 100)
                                }
                                .disabled(inspectionOnly)
                                .opacity(inspectionOnly ? 0.7 : 1.0)
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                HStack {
                    Text("UV Scale")
                        .font(.callout)
                        .foregroundColor(.editorTextSecondary)

                    TextInputNumberView(
                        label: "",
                        value: Binding(
                            get: { getMaterialSTScale(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialSTScale(entityId: entityId, stScale: newValue, meshIndex: meshIndex)
                                EditorSceneDirtyState.shared.markDirty()
                                refreshView()
                            }
                        )
                    )
                    .frame(width: 60)
                    .disabled(inspectionOnly)
                    .opacity(inspectionOnly ? 0.7 : 1.0)
                }

                Divider()
                HStack {
                    // Base Color Picker
                    VStack {
                        ColorPicker("", selection: Binding(
                            get: { colorFromSimd(getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)) },
                            set: { newColor in
                                updateMaterialColor(entityId: entityId, color: newColor, meshIndex: meshIndex)
                                EditorSceneDirtyState.shared.markDirty()
                            }
                        ))
                        .frame(width: 60)
                        .disabled(inspectionOnly)
                        .opacity(inspectionOnly ? 0.7 : 1.0)

                        Text("Base Color")
                            .font(.caption)
                    }

                    // Roughness Input
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialRoughness(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialRoughness(entityId: entityId, roughness: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Roughness")
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                    }

                    // Metallic Input
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialMetallic(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialMetallic(entityId: entityId, metallic: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Metallic")
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                    }
                }

                HStack {
                    // Height Scale Input — total Parallax Occlusion Mapping ray-march depth,
                    // in UV-normalized units. Only has a visible effect once a Height texture
                    // is assigned above.
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialHeightScale(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialHeightScale(entityId: entityId, heightScale: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Height Scale")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Midlevel Input — matches Blender's Displacement node "Midlevel"
                    // (default 0.5 = no shift).
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialHeightMidlevel(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialHeightMidlevel(entityId: entityId, heightMidlevel: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Midlevel")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // POM Enabled Toggle — lets testers A/B compare normal-mapping-only vs.
                    // normal+POM without discarding the height texture assignment.
                    VStack {
                        Toggle(isOn: Binding(
                            get: { getMaterialHeightEnabled(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialHeightEnabled(entityId: entityId, heightEnabled: newValue, meshIndex: meshIndex)
                                EditorSceneDirtyState.shared.markDirty()
                                if inspectionOnly, isUntoldBackedMesh {
                                    hasPendingUntoldWrite = true
                                    untoldUpdateStatus = nil
                                }
                                refreshView()
                            }
                        )) {
                            EmptyView()
                        }
                        .toggleStyle(.checkbox)
                        .frame(width: 60)

                        Text("POM Enabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    // Height Remap Min/Max — contrast-stretch the raw height sample before
                    // Midlevel is applied. Many real-world displacement maps (Substance/
                    // Poliigon exports especially) only use a narrow slice of the full [0,1]
                    // range, leaving POM almost no local contrast to work with even at a
                    // reasonable Height Scale. Identity is (0.0, 1.0).
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialHeightRemapMin(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialHeightRemapMin(entityId: entityId, heightRemapMin: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Height Remap Min")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialHeightRemapMax(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialHeightRemapMax(entityId: entityId, heightRemapMax: newValue, meshIndex: meshIndex)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Height Remap Max")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialOpacity(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialOpacity(entityId: entityId, opacity: newValue, meshIndex: meshIndex, submeshIndex: 0)
                                    EditorSceneDirtyState.shared.markDirty()
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Opacity")
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                    }

                    VStack {
                        Picker("", selection: Binding(
                            get: { getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialAlphaMode(entityId: entityId, mode: newValue, meshIndex: meshIndex)
                                EditorSceneDirtyState.shared.markDirty()
                                if inspectionOnly, isUntoldBackedMesh {
                                    hasPendingUntoldWrite = true
                                    untoldUpdateStatus = nil
                                }
                                refreshView()
                            }
                        )) {
                            ForEach(MaterialAlphaMode.allCases) { mode in
                                Text(mode.description).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)

                        Text("Alpha Mask")
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                    }
                }

                if inspectionOnly, isUntoldBackedMesh, hasPendingUntoldWrite {
                    Button(action: updateUntoldAsset) {
                        Text("Update .untold")
                    }
                    .buttonStyle(.borderedProminent)

                    if let untoldUpdateStatus {
                        Text(untoldUpdateStatus)
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                    }
                }

                VStack {
                    TextInputVectorView(
                        label: "",
                        value: Binding(
                            get: { getMaterialEmmissive(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialEmmisive(entityId: entityId, emmissive: newValue, meshIndex: meshIndex)
                                EditorSceneDirtyState.shared.markDirty()
                                refreshView()
                            }
                        )
                    )
                    .frame(width: 200)
                    .disabled(inspectionOnly)
                    .opacity(inspectionOnly ? 0.7 : 1.0)

                    Text("Emmisive")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                }
            }
        }
        .onAppear {
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
        .onChange(of: entityId) { _ in
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
        .onChange(of: meshIndex) { _ in
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
    }

    private var meshLabel: String {
        guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
              renderComponent.mesh.indices.contains(meshIndex)
        else {
            return getAssetURLString(entityId: entityId) ?? " "
        }

        let mesh = renderComponent.mesh[meshIndex]
        let name = mesh.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if inspectionOnly, !name.isEmpty {
            return name
        }

        return getAssetURLString(entityId: entityId) ?? (name.isEmpty ? " " : name)
    }

    private var isUntoldBackedMesh: Bool {
        resolveUntoldAssetURL(entityId: entityId) != nil
    }

    private func updateUntoldAsset() {
        do {
            try persistAlphaMaterialOverridesToUntold(
                entityId: entityId,
                meshIndex: meshIndex,
                opacity: getMaterialOpacity(entityId: entityId, meshIndex: meshIndex),
                alphaCutoff: getMaterialAlphaCutoff(entityId: entityId, meshIndex: meshIndex),
                roughness: getMaterialRoughness(entityId: entityId, meshIndex: meshIndex),
                metallic: getMaterialMetallic(entityId: entityId, meshIndex: meshIndex),
                alphaMode: getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex)
            )
            hasPendingUntoldWrite = false
            untoldUpdateStatus = "Updated \(resolveUntoldAssetURL(entityId: entityId)?.lastPathComponent ?? ".untold")"
            refreshView()
        } catch {
            untoldUpdateStatus = error.localizedDescription
        }
    }
}
