//
//  AssetBrowserView+Contents.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

extension AssetBrowserView {
    @ViewBuilder
    var rightPaneContents: some View {
        if navigation.lightsSelected {
            lightsShelfView
        } else if navigation.primitivesSelected {
            primitivesShelfView
        } else if navigation.entitiesSelected {
            entitiesShelfView
        } else if let selectedDirURL {
            folderContentsView(for: selectedDirURL, selectionManager: selectionManager)
        } else if let selectedCategory {
            let isScripts = (selectedCategory == AssetCategory.scripts.rawValue)
            if let currentFolderPath, !isScripts {
                folderContentsView(for: currentFolderPath, selectionManager: selectionManager)
            } else if let categoryAssets = assets[selectedCategory] {
                let filtered = categoryAssets.filter { matchesSearch($0) }
                let categoryRoot = AssetCategory(rawValue: selectedCategory).flatMap(categoryRootURL)
                let placeholders = categoryRoot.map { placeholderImports(pendingImports, in: $0) } ?? []
                if filtered.isEmpty, placeholders.isEmpty {
                    Text("No assets available")
                        .foregroundColor(.editorTextTertiary)
                        .padding()
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        assetRowList(filtered, spacing: 4) { asset in
                            if !isScripts {
                                folderPathStack.append(asset.path)
                            }
                        }
                        if let categoryRoot {
                            importPlaceholderRows(in: categoryRoot)
                        }
                    }
                }
            } else {
                Text("No assets available")
                    .foregroundColor(.editorTextTertiary)
                    .padding()
            }
        } else {
            Text("Select a folder")
                .foregroundColor(.editorTextTertiary)
                .padding()
        }
    }

    func assetRow(_ asset: Asset) -> some View {
        let isRemote = asset.path.pathExtension.lowercased() == "remotestream"
        return HStack {
            Image(systemName: asset.isFolder ? "folder.fill" : isRemote ? "globe" : "cube.fill")
                .foregroundColor(isRemote ? .editorInfo : .editorTextTertiary)
            Text(asset.name)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            selectedAssetName == asset.name ? Color.editorFill : Color.clear
        )
        .cornerRadius(6)
    }

    /// Row for an import whose copy is still running: the icon and file name it will
    /// have, dimmed, with the copy progress (bytes so far of the total) or a spinner
    /// until the first bytes are reported. It is not selectable and has no gestures.
    func importPlaceholderRow(_ pending: PendingAssetImport) -> some View {
        HStack {
            Image(systemName: pending.isFolder ? "folder" : "doc")
                .foregroundColor(.editorTextTertiary)
            Text(pending.name)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(.editorTextTertiary)
            Spacer()
            if let progress = pending.progress, let fraction = progress.fraction {
                Text(assetCopyProgressDetail(progress))
                    .font(.caption)
                    .foregroundColor(.editorTextTertiary)
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
            } else {
                ProgressView()
                    .controlSize(.small)
                Text("Importing…")
                    .font(.caption)
                    .foregroundColor(.editorTextTertiary)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .help("Copying into the project — see the Tasks panel.")
    }

    func importPlaceholderRows(in folder: URL) -> some View {
        ForEach(placeholderImports(pendingImports, in: folder)) { pending in
            importPlaceholderRow(pending)
        }
    }

    /// Shared row list used by both the flat-category listing and
    /// folderContentsView. Only the folder-tap navigation differs per call site.
    func assetRowList(_ assets: [Asset], spacing: CGFloat, onFolderTap: @escaping (Asset) -> Void) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(assets) { asset in
                assetRow(asset)
                    // Rows drag into the viewport or the hierarchy; the drop decides
                    // whether the asset can be placed (see AssetPlacement.swift).
                    .draggable(AssetDragPayload(asset: asset))
                    .contextMenu {
                        if asset.category == AssetCategory.gaussians.rawValue,
                           ["ply", "spz"].contains(asset.path.pathExtension.lowercased())
                        {
                            Button {
                                requestGaussianCook(of: [asset.path])
                            } label: {
                                Label("Cook to .untoldgs…", systemImage: "sparkles")
                            }
                        }
                        if sourceAssetExtensions.contains(asset.path.pathExtension.lowercased()) {
                            // A source kept in the project after import: convert it again
                            // (same folder as the original import) with fresh options.
                            if asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue,
                               let category = AssetCategory(rawValue: asset.category)
                            {
                                Button {
                                    queueRuntimeExport(
                                        sourceURL: asset.path,
                                        category: category,
                                        destinationFolder: asset.path.deletingLastPathComponent()
                                    )
                                } label: {
                                    Label("Cook to .untold…", systemImage: "sparkles")
                                }
                            } else if asset.category == AssetCategory.streamModels.rawValue {
                                Button {
                                    queueTilesExport(
                                        sourceURL: asset.path,
                                        destinationFolder: asset.path.deletingLastPathComponent()
                                    )
                                } label: {
                                    Label("Cook to tiled stream model…", systemImage: "sparkles")
                                }
                            }
                        }
                        Button(role: .destructive) {
                            pendingDeleteAsset = asset
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .modifier(AssetRowClickGestures(
                        isFolder: asset.isFolder,
                        onClick: {
                            if asset.isFolder {
                                onFolderTap(asset)
                            } else {
                                selectAsset(asset)
                            }
                        },
                        onDoubleClick: {
                            handle_add_model_double_click(asset: asset)
                        }
                    ))
            }
        }
    }

    @ViewBuilder
    func folderContentsView(for folder: URL, selectionManager _: SelectionManager) -> some View {
        if let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let items = contents.compactMap { item -> Asset? in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                    let itemCategory = selectedCategory ?? inferCategory(for: item)?.rawValue ?? ""
                    if isDir.boolValue {
                        return Asset(name: item.lastPathComponent, category: itemCategory, path: item, isFolder: true)
                    } else {
                        // Imported sources (USD, .blend) are listed too: they stay in the
                        // project beside their cooked output and can be re-converted.
                        let itemExtension = item.pathExtension.lowercased()
                        let categoryRuntimeExtensions = AssetCategory(rawValue: itemCategory)
                            .map { runtimeAssetExtensions(for: $0) } ?? allRuntimeAssetExtensions
                        let allowedExtensions: Set<String> = Set(["utex", "png", "jpg", "jpeg", "hdr", "exr", "cube", "tif", "tiff", "ply", "spz", "untoldgs", "json", "uscript", "remotestream"])
                            .union(categoryRuntimeExtensions)
                            .union(sourceAssetExtensions)
                        guard allowedExtensions.contains(itemExtension) else { return nil }

                        return Asset(name: item.lastPathComponent,
                                     category: itemCategory,
                                     path: item)
                    }
                }
                return nil
            }

            VStack(alignment: .leading, spacing: 8) {
                assetRowList(items.filter { matchesSearch($0) }, spacing: 8) { asset in
                    if selectedDirURL != nil {
                        // Generic navigation (root-level / custom folders)
                        selectedDirURL = asset.path
                    } else if selectedCategory != AssetCategory.scripts.rawValue {
                        folderPathStack.append(asset.path)
                    }
                }
                importPlaceholderRows(in: folder)
            }
        } else {
            Text("Folder is empty or inaccessible.")
                .foregroundColor(.editorTextTertiary)
                .padding()
        }
    }
}
