//
//  AssetBrowserView.swift
//
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

struct AssetBrowserView: View {
    @Binding var assets: [String: [Asset]]
    @Binding var selectedAsset: Asset?
    /// Navigation lives outside the view so it survives the browser being
    /// removed from the hierarchy (e.g. while the Console tab is showing).
    @ObservedObject var navigation = AssetBrowserNavigationState()
    @ObservedObject var editorBaseAssetPath = EditorAssetBasePath.shared
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel

    var selectedCategory: String? {
        get { navigation.selectedCategory }
        nonmutating set { navigation.selectedCategory = newValue }
    }

    var selectedAssetName: String? {
        get { navigation.selectedAssetName }
        nonmutating set { navigation.selectedAssetName = newValue }
    }

    var folderPathStack: [URL] {
        get { navigation.folderPathStack }
        nonmutating set { navigation.folderPathStack = newValue }
    }

    var expandedDirs: Set<URL> {
        get { navigation.expandedDirs }
        nonmutating set { navigation.expandedDirs = newValue }
    }

    var selectedDirURL: URL? {
        get { navigation.selectedDirURL }
        nonmutating set { navigation.selectedDirURL = newValue }
    }

    var rootExpanded: Bool {
        get { navigation.rootExpanded }
        nonmutating set { navigation.rootExpanded = newValue }
    }

    @State var showUnsavedChangesAlert = false
    @State var unsavedChangesAlertMessage = ""
    @State var showDeleteConfirmation = false
    @State var pendingDeleteAsset: Asset?
    @State var showBasePathAlert = false
    @State var showBlockedDuringPlayAlert = false
    @Binding var searchQuery: String
    @State var statusMessage: String?
    @State var statusIsError = false
    @State var targetEntityName: String = "None"
    @State var showImportMenu = false
    @State var showRemoteStreamSheet = false
    @State var remoteStreamURLString = ""
    /// The cook sheet's item: the `.ply`/`.spz` of the row whose "Cook to .untoldgs…" was chosen.
    /// Presented with `.sheet(item:)`, so the sheet exists only while there is a request,
    /// and a request always carries sources (`GaussianCookRequest.init?(sources:)`).
    @State var pendingGaussianCook: GaussianCookRequest?
    @State var gaussianCookSettings = GaussianCookSettings()
    /// Import copies still running (see `AssetImportCopy.swift`). Past the placeholder
    /// delay each one is drawn as a placeholder row in the folder that will receive it.
    @State var pendingImports: [PendingAssetImport] = []
    @State var pendingRuntimeExport: RuntimeExportRequest?
    @State var runtimeExportQueue: [RuntimeExportRequest] = []
    @State var isExportingRuntimeAsset = false
    /// Requests confirmed via "Cook" while another export was already running;
    /// drained one at a time by finishRuntimeExport().
    @State var runtimeExportWorkQueue: [RuntimeExportRequest] = []
    @State var exportConvertOrientation = true
    @State var exportSourceOrientation = "blender-native"
    @State var pendingTilesExport: TilesExportRequest?
    @State var tilesExportQueue: [TilesExportRequest] = []
    @State var isExportingTilesAsset = false
    /// Same as runtimeExportWorkQueue, for tiled stream-model exports.
    @State var tilesExportWorkQueue: [TilesExportRequest] = []
    @State var exportTileSizeX: String = "25"
    @State var exportTileSizeY: String = "10000"
    @State var exportTileSizeZ: String = "25"
    @State var exportCompressGeometry = false
    @State var exportCompressTextures = false
    @State var astcencBinPath: String = ""
    @State var exportQuadTree = false
    @State var exportAutoTileSize = false
    @State var exportGenerateHLOD = false
    @State var exportGenerateLOD = false
    @State var exportDryRun = false
    var editor_addEntityWithAsset: () -> Void
    var editor_loadSceneAuthoredFromAsset: (Asset) -> Void = { _ in }
    var currentFolderPath: URL? {
        folderPathStack.last
    }

    var body: some View {
        ZStack {
            Color.editorBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                // MARK: - Finder-style split: directory tree | folder contents

                HStack(spacing: 8) {
                    // Left: directory tree with a root node (right-click any
                    // folder — including the root — to create a subfolder).
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 2) {
                            rootDirectoryRow

                            if rootExpanded {
                                primitivesCategoryRow
                                lightsCategoryRow
                                entitiesCategoryRow

                                ForEach(AssetCategory.allCases, id: \.self) { category in
                                    directoryNode(
                                        url: categoryRootURL(category),
                                        name: category.displayName,
                                        category: category.rawValue,
                                        depth: 1
                                    )
                                }
                                ForEach(customRootFolders, id: \.self) { url in
                                    directoryNode(
                                        url: url,
                                        name: url.lastPathComponent,
                                        category: nil,
                                        depth: 1
                                    )
                                }
                            }
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: 225)
                    .frame(maxHeight: .infinity)
                    .background(Color.editorFillSubtle)
                    .cornerRadius(8)
                    .help("Right-click a folder to create a new directory. Select a folder to choose where imports go.")

                    // Right: contents of the selected directory
                    ScrollView(.vertical, showsIndicators: true) {
                        rightPaneContents
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.editorSurface.opacity(0.7))
                    .cornerRadius(8)
                    // Double-click on the empty area (not a row: rows own their own
                    // double-click, which places the asset) opens the same import dialog
                    // as the context menu, for the folder currently shown.
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        importIntoCurrentDirectory()
                    }
                    .help("Double-click or right-click this area to import assets into the selected folder.")
                    .contextMenu {
                        Button {
                            importIntoCurrentDirectory()
                        } label: {
                            Label("Import…", systemImage: "plus.circle")
                        }
                        Button {
                            showRemoteStreamSheet = true
                        } label: {
                            Label("Import Remote Stream", systemImage: "globe")
                        }
                        if selectedSceneAuthoredAsset() != nil {
                            Divider()
                            Button {
                                loadSelectedSceneAuthoredPayload()
                            } label: {
                                Label("Load Authored", systemImage: "camera.badge.ellipsis")
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(10)
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            loadAssets()
            updateTargetEntityName(for: selectionManager.selectedEntity)
        }
        // Keep the target label in sync with editor selection changes.
        .onReceive(selectionManager.$selectedEntity) { entityId in
            updateTargetEntityName(for: entityId)
        }
        .onChange(of: editorBaseAssetPath.basePath) {
            loadAssets()
        }
        // Refresh when category changes (covers normal switching)
        .onChange(of: selectedCategory) { _, _ in
            loadAssets()
        }
        // Listen for external requests to reload assets (e.g., after saveScene copies into Scenes)
        .onReceive(NotificationCenter.default.publisher(for: .assetBrowserReload)) { _ in
            loadAssets()
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Cancel", role: .cancel) {
                EditorPendingSwitchAction.shared.cancel()
            }
            Button("Discard Changes", role: .destructive) {
                EditorPendingSwitchAction.shared.consume()
            }
            Button("Save") {
                NotificationCenter.default.post(name: .editorMenuSave, object: nil)
            }
        } message: {
            Text(unsavedChangesAlertMessage)
        }
        .alert("Stop Play Mode First", isPresented: $showBlockedDuringPlayAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This action is disabled while Play mode is running. Stop Play mode and try again.")
        }
        .alert("No Project Loaded", isPresented: $showBasePathAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please create a new project or open an existing project before importing assets.")
        }
        .alert("Delete Asset?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingDeleteAsset = nil
            }
            Button("Delete", role: .destructive) {
                if let asset = pendingDeleteAsset {
                    deleteAsset(asset)
                }
                pendingDeleteAsset = nil
            }
        } message: {
            if let asset = pendingDeleteAsset {
                Text("This will remove \(asset.name) from disk under your Asset Folder.")
            }
        }
        .sheet(item: $pendingRuntimeExport) { request in
            runtimeExportSheet(for: request)
        }
        .sheet(item: $pendingTilesExport) { request in
            tilesExportSheet(for: request)
        }
        .sheet(item: $pendingGaussianCook) { request in
            GaussianCookSheet(
                sourceURLs: request.sourceURLs,
                settings: $gaussianCookSettings,
                onCook: {
                    pendingGaussianCook = nil
                    cookGaussianSources(request.sourceURLs)
                },
                onCancel: {
                    pendingGaussianCook = nil
                }
            )
        }
        .sheet(isPresented: $showRemoteStreamSheet) {
            RemoteStreamImportSheet(urlString: $remoteStreamURLString) {
                saveRemoteStream(loadImmediately: true)
                showRemoteStreamSheet = false
            } onCancel: {
                remoteStreamURLString = ""
                showRemoteStreamSheet = false
            }
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(statusIsError ? Color.editorError.opacity(0.85) : Color.editorSuccess.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
