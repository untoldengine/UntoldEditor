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
    var breadcrumbBar: some View {
        if !navigation.lightsSelected, !navigation.primitivesSelected, !navigation.entitiesSelected,
           let current = currentDirectoryURL
        {
            let segments = breadcrumbSegments(for: current)
            HStack(spacing: 4) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.editorTextTertiary)
                    }
                    Button {
                        selectBreadcrumb(segment)
                    } label: {
                        Text(segment.name)
                            .font(.system(size: 12, weight: index == segments.count - 1 ? .semibold : .regular))
                            .foregroundColor(index == segments.count - 1 ? .editorTextPrimary : .editorTextSecondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()
        }
    }

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
        let isRenaming = asset.isFolder && navigation.renamingDirectoryURL?.standardizedFileURL == asset.path.standardizedFileURL
        return HStack {
            Image(systemName: asset.isFolder ? "folder.fill" : isRemote ? "globe" : "cube.fill")
                .foregroundColor(isRemote ? .editorInfo : .editorTextTertiary)
            if isRenaming {
                CommitTextField(text: asset.name, multiline: false) { newName in
                    renameFolder(at: asset.path, to: newName)
                }
            } else {
                Text(asset.name)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
            }
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
                        if asset.isFolder, canRenameFolder(at: asset.path) {
                            Button {
                                navigation.renamingDirectoryURL = asset.path
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button {
                                requestMoveFolder(asset.path)
                            } label: {
                                Label("Move to…", systemImage: "folder")
                            }
                            Divider()
                        }
                        let pathExtension = asset.path.pathExtension.lowercased()
                        if ["ply", "spz"].contains(pathExtension) {
                            Button {
                                requestGaussianCook(of: [asset.path])
                            } label: {
                                Label("Cook to .untoldgs…", systemImage: "sparkles")
                            }
                        } else if sourceAssetExtensions.contains(pathExtension) {
                            // A source kept in the project after import: convert it again
                            // with fresh options. A source still sitting where the legacy
                            // layout left it (beside its cooked output, inside GameData)
                            // keeps the category that location already fixed; a source in
                            // Resources/ has none yet, so every cook target is offered --
                            // the user decides what it becomes.
                            if let category = AssetCategory(rawValue: asset.category), category == .models || category == .animations {
                                Button {
                                    queueRuntimeExport(sourceURL: asset.path, category: category)
                                } label: {
                                    Label("Cook to .untold…", systemImage: "sparkles")
                                }
                            } else if asset.category == AssetCategory.streamModels.rawValue {
                                Button {
                                    queueTilesExport(
                                        sourceURL: asset.path,
                                        destinationFolder: tilesExportDestinationFolder(for: asset.path, assetBasePath: assetBasePath)
                                    )
                                } label: {
                                    Label("Cook to tiled stream model…", systemImage: "sparkles")
                                }
                            } else {
                                Button {
                                    queueRuntimeExport(sourceURL: asset.path, category: .models)
                                } label: {
                                    Label("Cook to .untold (Model)…", systemImage: "sparkles")
                                }
                                Button {
                                    queueRuntimeExport(sourceURL: asset.path, category: .animations)
                                } label: {
                                    Label("Cook to .untoldanim (Animation)…", systemImage: "sparkles")
                                }
                                Button {
                                    queueTilesExport(
                                        sourceURL: asset.path,
                                        destinationFolder: tilesExportDestinationFolder(for: asset.path, assetBasePath: assetBasePath)
                                    )
                                } label: {
                                    Label("Cook to Tiled Stream Model…", systemImage: "sparkles")
                                }
                            }
                        }
                        if let sourceFolder = asset.sourceFolder {
                            Button {
                                // The source folder is usually in Resources/ now -- a
                                // different root than wherever this asset itself is being
                                // browsed -- so this navigates generically rather than
                                // assuming it's reachable by staying in the same category's
                                // folder chain (see breadcrumbSegments/selectBreadcrumb).
                                navigation.lightsSelected = false
                                navigation.primitivesSelected = false
                                navigation.entitiesSelected = false
                                selectedDirURL = sourceFolder
                                selectedCategory = nil
                                folderPathStack = []
                                selectedAsset = nil
                                selectedAssetName = nil
                            } label: {
                                Label("Reveal Source Folder", systemImage: "folder")
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
            // A folder that shares its stem with a sibling runtime asset is that
            // asset's cook source (see `runtimeExportLocation`): it's not listed on
            // its own, only reachable via that asset's "Reveal Source Folder" menu.
            // (A no-op when `folder` is itself under Resources/: nothing there has a
            // runtime extension to match in the first place.)
            let sourceFolderByStem: [String: URL] = contents.reduce(into: [:]) { result, item in
                guard allRuntimeAssetExtensions.contains(item.pathExtension.lowercased()) else { return }
                let stem = item.deletingPathExtension().lastPathComponent
                if let found = sourceFolderCandidate(for: item, assetBasePath: assetBasePath) {
                    result[stem] = found
                }
            }

            let items = contents.compactMap { item -> Asset? in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                    let itemCategory = selectedCategory ?? inferCategory(for: item)?.rawValue ?? ""
                    if isDir.boolValue {
                        guard sourceFolderByStem[item.lastPathComponent] == nil else { return nil }
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

                        let sourceFolder = allRuntimeAssetExtensions.contains(itemExtension)
                            ? sourceFolderByStem[item.deletingPathExtension().lastPathComponent]
                            : nil

                        return Asset(name: item.lastPathComponent,
                                     category: itemCategory,
                                     path: item,
                                     sourceFolder: sourceFolder)
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
