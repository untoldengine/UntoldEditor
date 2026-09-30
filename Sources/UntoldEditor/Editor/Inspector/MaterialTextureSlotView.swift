//
//  MaterialTextureSlotView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
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

/// One texture slot of a material: its image, which a click replaces with the
/// material selected in Assets or a picked file, the remove and restore
/// buttons, and its wrap mode.
struct MaterialTextureSlotView: View {
    let entityId: EntityID
    let meshIndex: Int
    let type: TextureType
    let asset: Asset?
    let inspectionOnly: Bool
    let refreshView: () -> Void

    var body: some View {
        let textureURL = getMaterialTextureURL(entityId: entityId, type: type, meshIndex: meshIndex)
        let hoverText = editorMaterialSlotHoverText(textureType: type, textureURL: textureURL)
        let image: NSImage? = getMaterialTextureImage(entityId: entityId, type: type, meshIndex: meshIndex) ?? NSImage(named: "Default Texture")

        VStack(alignment: .center, spacing: 8) {
            Button(action: assignTexture) {
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

    private func assignTexture() {
        if asset?.category == AssetCategory.materials.rawValue, let path = asset?.path {
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
    }
}
