//
//  AssetBrowserView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

enum AssetCategory: String, CaseIterable {
    case models = "Models"
    case animations = "Animations"
    case scripts = "Scripts"
    case scenes = "Scenes"
    case gaussians = "Gaussians"
    case materials = "Materials"
    case hdr = "HDR"

    var iconName: String {
        switch self {
        case .models:
            return "cube.fill"
        case .animations:
            return "film"
        case .hdr:
            return "film"
        case .materials:
            return "film"
        case .gaussians:
            return "sparkles"
        case .scenes:
            return "house"
        case .scripts:
            return "pencil"
        }
    }
}

struct AssetBrowserView: View {
    @Binding var assets: [String: [Asset]]
    @Binding var selectedAsset: Asset?
    @State private var selectedCategory: String? = "Models" // Default category
    @State private var selectedAssetName: String?
    @ObservedObject var editorBaseAssetPath = EditorAssetBasePath.shared
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @State private var folderPathStack: [URL] = []
    @State private var showSceneLoadConfirmation = false
    @State private var pendingSceneToLoad: URL?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteAsset: Asset?
    @State private var showBasePathAlert = false
    @State private var searchQuery: String = ""
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var targetEntityName: String = "None"
    var editor_addEntityWithAsset: () -> Void
    private var currentFolderPath: URL? {
        folderPathStack.last
    }

    var body: some View {
        ZStack {
            Color.editorBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 8) {
                // MARK: - Top Bar

                HStack {
                    Text("Assets")
                        .font(.title3)
                        .bold()
                        .foregroundColor(.white)

                    Button(action: importAsset) {
                        HStack(spacing: 6) {
                            Text("Import Asset")
                            Image(systemName: "plus.circle")
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.editorAccent)
                        .foregroundColor(.black.opacity(0.9))
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Button(action: promptDeleteAsset) {
                        HStack(spacing: 6) {
                            Text("Delete")
                            Image(systemName: "trash")
                                .foregroundColor(.white)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(selectedAsset == nil ? Color.gray.opacity(0.5) : Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(selectedAsset == nil)

                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                        TextField("Filter assets", text: $searchQuery)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .frame(maxWidth: 240)

                    Spacer()

                    // Set Base Path Button
                    Button(action: selectResourceDirectory) {
                        HStack(spacing: 6) {
                            Image(systemName: "externaldrive.fill.badge.plus")
                                .foregroundColor(.white)
                            Text("Asset Folder")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.editorSurface)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.editorPanelBackground.opacity(0.9))
                .cornerRadius(8)

                // MARK: - Path Indicator

                HStack(spacing: 12) {
                    if let resourceDir = editorBaseAssetPath.basePath {
                        Text("Current Path: \(resourceDir.lastPathComponent)")
                            .font(.caption)
                            .foregroundColor(Color.editorAccent)
                    } else {
                        Text("No Path Selected")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    Spacer()

                    Text("Target Entity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(targetEntityName)
                        .font(.caption)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 5)

                // MARK: - Sidebar and Asset List Layout

                HStack(spacing: 8) {
                    // MARK: - Sidebar

                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Categories")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.bottom, 2)

                            ForEach(AssetCategory.allCases, id: \.self) { category in
                                HStack {
                                    Image(systemName: selectedCategory == category.rawValue ? "folder.fill" : "folder")
                                        .foregroundColor(selectedCategory == category.rawValue ? Color.editorAccent : .gray)
                                    Text(category.rawValue)
                                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                                        .foregroundColor(selectedCategory == category.rawValue ? .white : .primary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .background(selectedCategory == category.rawValue ? Color.editorAccentSoft : Color.clear)
                                .cornerRadius(6)
                                .onTapGesture {
                                    // If reselecting the same category, force a reload
                                    if selectedCategory == category.rawValue {
                                        loadAssets()
                                    } else {
                                        selectedCategory = category.rawValue
                                    }
                                    // Reset folder navigation when switching category,
                                    // but Scripts will not use folder navigation at all.
                                    folderPathStack = []
                                }
                            }
                        }
                        .padding(8)
                    }

                    .frame(width: 140)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)

                    // MARK: - Asset List

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let selectedCategory {
                                // Scripts: flat, no breadcrumbs or folders
                                let isScripts = (selectedCategory == AssetCategory.scripts.rawValue)

                                if !isScripts, !folderPathStack.isEmpty {
                                    // Show breadcrumb if inside folders (non-Scripts only)
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 4) {
                                            Button("Assets") {
                                                folderPathStack = []
                                            }

                                            ForEach(Array(folderPathStack.enumerated()), id: \.element) { index, url in
                                                Text(">")
                                                Button(url.lastPathComponent) {
                                                    folderPathStack = Array(folderPathStack.prefix(upTo: index + 1))
                                                }
                                            }
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.05))
                                        .cornerRadius(6)
                                    }
                                }

                                // Show either folder contents or top-level categories
                                if let currentFolderPath, !isScripts {
                                    folderContentsView(for: currentFolderPath, selectionManager: selectionManager)
                                } else {
                                    if let categoryAssets = assets[selectedCategory] {
                                        ForEach(categoryAssets.filter { matchesSearch($0) }) { asset in
                                            // For Scripts, we never navigate into folders (we won't list folders anyway)
                                            assetRow(asset)
                                                .onTapGesture(count: 2) {
                                                    handle_add_model_double_click(asset: asset)
                                                }
                                                .onTapGesture(count: 1) {
                                                    if asset.isFolder {
                                                        // Only allow folder navigation for non-Scripts categories
                                                        if !isScripts {
                                                            folderPathStack.append(asset.path)
                                                        }
                                                    } else {
                                                        selectAsset(asset)
                                                    }
                                                }
                                        }
                                    } else {
                                        Text("No assets available")
                                            .foregroundColor(.gray)
                                            .padding()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(maxHeight: 300)
                    .background(Color.editorSurface.opacity(0.7))
                    .cornerRadius(8)
                }
                .frame(maxHeight: 300)
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
        .alert("Load Scene?", isPresented: $showSceneLoadConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingSceneToLoad = nil
            }
            Button("Load Scene", role: .destructive) {
                if let sceneURL = pendingSceneToLoad {
                    loadScene(from: sceneURL)
                }
                pendingSceneToLoad = nil
            }
        } message: {
            Text("Loading a new scene will replace the current scene. Any unsaved changes will be lost.")
        }
        .alert("Set Asset Folder First", isPresented: $showBasePathAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please set the Asset Folder in the Asset Browser before importing assets.")
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
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(statusIsError ? Color.red.opacity(0.85) : Color.green.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Select Resource Directory

    private func selectResourceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let selectedURL = panel.urls.first {
            // Create the required folder structure if it doesn't exist
            let fm = FileManager.default
            let requiredFolders = ["Models", "Animations", "HDR", "Gaussians", "Materials", "Scenes", "Scripts"]

            for folder in requiredFolders {
                let folderURL = selectedURL.appendingPathComponent(folder, isDirectory: true)
                if !fm.fileExists(atPath: folderURL.path) {
                    try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
                }
            }

            assetBasePath = selectedURL
            EditorAssetBasePath.shared.basePath = assetBasePath
        }
    }

    private func importAsset() {
        guard editorBaseAssetPath.basePath != nil else {
            showBasePathAlert = true
            return
        }

        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "usdz")!,
            .png, .jpeg, .tiff,
            UTType(filenameExtension: "hdr")!,
            UTType(filenameExtension: "ply")!,
            UTType(filenameExtension: "json")!,
            UTType(filenameExtension: "uscript")!,
        ]
        openPanel.canChooseDirectories = (selectedCategory == "Materials")
        openPanel.allowsMultipleSelection = true

        guard let basePath = assetBasePath else { return }
        // Supported categories must match your enum/string values
        guard ["Models", "Animations", "HDR", "Materials", "Gaussians", "Scenes", "Scripts"].contains(selectedCategory) else { return }

        let fm = FileManager.default
        let categoryRoot = basePath.appendingPathComponent(selectedCategory!, isDirectory: true)
        // Ensure category folder exists (e.g., <Base>/Models)
        try? fm.createDirectory(at: categoryRoot, withIntermediateDirectories: true)

        if openPanel.runModal() == .OK {
            for sourceURL in openPanel.urls {
                do {
                    switch selectedCategory {
                    case "HDR":
                        // Copy .hdr directly into HDR folder
                        let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
                        try fm.copyItem(at: sourceURL, to: destURL)

                    case "Gaussians":
                        // Copy Gaussian files directly into Gaussians folder
                        let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
                        try fm.copyItem(at: sourceURL, to: destURL)

                    case "Materials":
                        if sourceURL.hasDirectoryPath {
                            // Copy entire material folder (recommended)
                            let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                            if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
                            try fm.copyItem(at: sourceURL, to: destURL)
                        } else {
                            // Single texture fallback → create folder named after the file (without ext)
                            let baseName = sourceURL.deletingPathExtension().lastPathComponent
                            let materialFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                            if fm.fileExists(atPath: materialFolder.path) { try fm.removeItem(at: materialFolder) }
                            try fm.createDirectory(at: materialFolder, withIntermediateDirectories: true)
                            let destFile = materialFolder.appendingPathComponent(sourceURL.lastPathComponent)
                            try fm.copyItem(at: sourceURL, to: destFile)
                        }

                    case "Models", "Animations":
                        // Create <Category>/<name>/ and copy the .usdc
                        let baseName = sourceURL.deletingPathExtension().lastPathComponent
                        let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                        try fm.createDirectory(at: destFolder, withIntermediateDirectories: true)

                        let destModel = destFolder.appendingPathComponent(sourceURL.lastPathComponent)
                        if fm.fileExists(atPath: destModel.path) { try fm.removeItem(at: destModel) }
                        try fm.copyItem(at: sourceURL, to: destModel)

                        // For Models: also copy sibling "textures" folder if it exists
                        if selectedCategory == "Models" {
                            let textureFolderSource = sourceURL.deletingLastPathComponent().appendingPathComponent("textures", isDirectory: true)
                            let textureFolderDest = destFolder.appendingPathComponent("textures", isDirectory: true)
                            var isDir: ObjCBool = false
                            if fm.fileExists(atPath: textureFolderSource.path, isDirectory: &isDir), isDir.boolValue {
                                if fm.fileExists(atPath: textureFolderDest.path) { try fm.removeItem(at: textureFolderDest) }
                                try fm.copyItem(at: textureFolderSource, to: textureFolderDest)
                            }
                        }

                    case "Scenes":
                        // Copy Scenes files directly into Scenes folder
                        let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
                        try fm.copyItem(at: sourceURL, to: destURL)

                    case "Scripts":
                        // Copy Scripts files directly into Scripts folder
                        let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                        if fm.fileExists(atPath: destURL.path) { try fm.removeItem(at: destURL) }
                        try fm.copyItem(at: sourceURL, to: destURL)

                    default:
                        break
                    }
                } catch {
                    print("Error copying \(sourceURL.lastPathComponent): \(error)")
                }
            }

            loadAssets()
            showStatus("Queued import of \(openPanel.urls.count) item(s) (see Console)")
        }
    }

    private func promptDeleteAsset() {
        guard let asset = selectedAsset else { return }
        pendingDeleteAsset = asset
        showDeleteConfirmation = true
    }

    // MARK: - Load Assets

    private func loadAssets() {
        guard editorBaseAssetPath.basePath != nil else { return }
        guard let basePath = assetBasePath else { return }

        var groupedAssets: [String: [Asset]] = [:]

        for category in AssetCategory.allCases {
            let categoryPath = basePath.appendingPathComponent(category.rawValue, isDirectory: true)
            var categoryAssets: [Asset] = []

            if category == .scripts {
                // Flat list of .uscript files anywhere under Scripts
                let uscriptURLs = findFilesRecursively(at: categoryPath, withExtension: "uscript")
                for url in uscriptURLs {
                    categoryAssets.append(
                        Asset(name: url.lastPathComponent,
                              category: category.rawValue,
                              path: url,
                              isFolder: false)
                    )
                }
                // Sort for stable UI
                categoryAssets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                groupedAssets[category.rawValue] = categoryAssets
                continue
            }

            // Flat list for Models and Animations - show .usdz files directly
            if category == .models || category == .animations {
                let usdzURLs = findFilesRecursively(at: categoryPath, withExtension: "usdz")
                for url in usdzURLs {
                    categoryAssets.append(
                        Asset(name: url.lastPathComponent,
                              category: category.rawValue,
                              path: url,
                              isFolder: false)
                    )
                }
                // Sort for stable UI
                categoryAssets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                groupedAssets[category.rawValue] = categoryAssets
                continue
            }

            // Non-Scripts categories: list immediate children, with folder navigation support
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: categoryPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for item in contents {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            // It’s a folder — valid for all categories
                            categoryAssets.append(Asset(name: item.lastPathComponent,
                                                        category: category.rawValue,
                                                        path: item,
                                                        isFolder: true))
                        } else if category == .hdr {
                            // For HDR, also allow .hdr files directly in the HDR folder
                            if item.pathExtension.lowercased() == "hdr" {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .gaussians {
                            // For Gaussians, allow gaussian files directly in the Gaussians folder
                            categoryAssets.append(Asset(name: item.lastPathComponent,
                                                        category: category.rawValue,
                                                        path: item,
                                                        isFolder: false))
                        } else if category == .scripts {
                            // Not used anymore due to flat listing, but keep for safety (won’t execute due to continue above)
                        } else if category == .scenes {
                            // For Scenes, allow files directly in the Scenes folder
                            categoryAssets.append(Asset(name: item.lastPathComponent,
                                                        category: category.rawValue,
                                                        path: item,
                                                        isFolder: false))
                        }
                    }
                }
            }

            groupedAssets[category.rawValue] = categoryAssets
        }

        assets = groupedAssets
    }

    private func matchesSearch(_ asset: Asset) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        return asset.name.localizedCaseInsensitiveContains(query)
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    // Recursively find all files with a specific extension under a root directory
    private func findFilesRecursively(at root: URL, withExtension ext: String) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == ext.lowercased() {
                results.append(url)
            }
        }

        return results
    }

    @ViewBuilder
    private func assetRow(_ asset: Asset) -> some View {
        HStack {
            Image(systemName: asset.isFolder ? "folder.fill" : "cube.fill")
                .foregroundColor(.gray)
            Text(asset.name)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            selectedAssetName == asset.name ? Color.secondary.opacity(0.1) : Color.clear
        )
        .cornerRadius(6)
    }

    @ViewBuilder
    private func folderContentsView(for folder: URL, selectionManager _: SelectionManager) -> some View {
        if let contents = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            let items = contents.compactMap { item -> Asset? in
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        return Asset(name: item.lastPathComponent, category: selectedCategory ?? "", path: item, isFolder: true)
                    } else {
                        let allowedExtensions: Set<String> = ["usdz", "png", "jpg", "hdr", "tif", "ply", "json", "uscript"]
                        guard allowedExtensions.contains(item.pathExtension) else { return nil }

                        return Asset(name: item.lastPathComponent,
                                     category: selectedCategory ?? "",
                                     path: item)
                    }
                }
                return nil
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items.filter { matchesSearch($0) }) { asset in
                    assetRow(asset)
                        .onTapGesture(count: 2) {
                            handle_add_model_double_click(asset: asset)
                        }
                        .onTapGesture(count: 1) {
                            if asset.isFolder {
                                // Only navigate for non-Scripts categories
                                if selectedCategory != AssetCategory.scripts.rawValue {
                                    folderPathStack.append(asset.path)
                                }
                            } else {
                                selectAsset(asset)
                            }
                        }
                }
            }
        } else {
            Text("Folder is empty or inaccessible.")
                .foregroundColor(.gray)
                .padding()
        }
    }

    // MARK: - Select Asset

    private func selectAsset(_ asset: Asset) {
        selectedAsset = asset
        selectedAssetName = asset.name
        updateTargetEntityName(for: selectionManager.selectedEntity)
    }

    // MARK: - Delete Asset

    private func deleteAsset(_ asset: Asset) {
        guard let basePath = assetBasePath else {
            showBasePathAlert = true
            return
        }

        // Ensure the asset lives under the base path before deleting
        guard asset.path.resolvingSymlinksInPath().path.hasPrefix(basePath.resolvingSymlinksInPath().path) else {
            print("⚠️ Refusing to delete asset outside base path: \(asset.path.path)")
            showStatus("Cannot delete outside Asset Folder", isError: true)
            return
        }

        do {
            try FileManager.default.removeItem(at: asset.path)
            print("✅ Deleted asset: \(asset.name)")
            if selectedAsset?.id == asset.id {
                selectedAsset = nil
                selectedAssetName = nil
            }
            loadAssets()
            showStatus("Queued delete: \(asset.name) (see Console)")
        } catch {
            print("❌ Failed to delete asset \(asset.name): \(error)")
            showStatus("Delete failed for \(asset.name) (see Console)", isError: true)
        }
    }

    // MARK: - Add Model with Double Click

    private func handle_add_model_double_click(asset: Asset) {
        // Don't handle folders
        guard !asset.isFolder else { return }

        let filename = asset.path.deletingPathExtension().lastPathComponent
        let withExtension = asset.path.pathExtension

        // Handle model files (usdz)
        if asset.category == AssetCategory.models.rawValue,
           withExtension.lowercased() == "usdz"
        {
            // Create entity
            let entityId = createEntity()

            // Use a generated name to avoid duplicate names when importing repeatedly
            let uniqueName = generateEntityName()
            setEntityName(entityId: entityId, name: uniqueName)

            // Add mesh to entity asynchronously
            setEntityMeshAsync(entityId: entityId, filename: filename, withExtension: withExtension) { success in
                if success {
                    print("✅ Model imported: \(uniqueName)")
                } else {
                    print("⚠️ Failed to load model, using fallback: \(uniqueName)")
                }
                // Refresh scene hierarchy after loading completes
                sceneGraphModel.refreshHierarchy()
            }

            // Select the newly created entity in the editor
            selectionManager.selectedEntity = entityId

            showStatus("Importing model: \(uniqueName)...")
        }
        // Handle Gaussian files (ply)
        else if asset.category == AssetCategory.gaussians.rawValue,
                withExtension.lowercased() == "ply"
        {
            // Create entity
            let entityId = createEntity()

            // Use a generated name to avoid duplicate names when importing repeatedly
            let uniqueName = generateEntityName()
            setEntityName(entityId: entityId, name: uniqueName)

            // Add Gaussian component to entity
            setEntityGaussian(entityId: entityId, filename: filename, withExtension: withExtension)

            // Refresh the scene hierarchy to show the new entity
            sceneGraphModel.refreshHierarchy()

            // Select the newly created entity in the editor
            selectionManager.selectedEntity = entityId

            showStatus("Queued Gaussian import: \(uniqueName) (see Console)")
        }
        // Handle Animation files (usdz in Animations category)
        else if asset.category == AssetCategory.animations.rawValue,
                withExtension.lowercased() == "usdz"
        {
            // Animations require a selected entity to work with
            guard let entityId = selectionManager.selectedEntity,
                  entityId != .invalid
            else {
                print("⚠️ Please select an entity first to add animation")
                showStatus("Select an entity before adding animation", isError: true)
                return
            }

            // Add AnimationComponent if not already present
            if !hasComponent(entityId: entityId, componentType: AnimationComponent.self) {
                registerComponent(entityId: entityId, componentType: AnimationComponent.self)
            }

            // Add the animation to the entity
            setEntityAnimations(entityId: entityId, filename: filename, withExtension: withExtension, name: filename)

            // Store the animation file URL in the component
            if let animationComponent = scene.get(component: AnimationComponent.self, for: entityId) {
                animationComponent.animationsFilenames.append(asset.path)
            }

            // Refresh view
            selectionManager.objectWillChange.send()
            showStatus("Queued animation link to \(targetEntityName) (see Console)")
        }
        // Handle Script files (uscript)
        else if asset.category == AssetCategory.scripts.rawValue,
                withExtension.lowercased() == "uscript"
        {
            // Scripts require a selected entity to work with
            guard let entityId = selectionManager.selectedEntity,
                  entityId != .invalid
            else {
                print("⚠️ Please select an entity first to add script")
                showStatus("Select an entity before adding script", isError: true)
                return
            }

            // Get or create ScriptComponent
            let scriptComponent: ScriptComponent
            if let existing = scene.get(component: ScriptComponent.self, for: entityId) {
                scriptComponent = existing
            } else {
                guard let newComp = scene.assign(to: entityId, component: ScriptComponent.self) else {
                    print("❌ Failed to create ScriptComponent")
                    return
                }
                scriptComponent = newComp
            }

            // Load and append the script
            do {
                let jsonData = try Data(contentsOf: asset.path)
                let decoder = JSONDecoder()
                let loadedScript = try decoder.decode(USCScript.self, from: jsonData)

                // Append script and its path
                scriptComponent.scripts.append(loadedScript)
                if scriptComponent.scriptFilePaths == nil {
                    scriptComponent.scriptFilePaths = []
                }
                scriptComponent.scriptFilePaths?.append(asset.path.path)

                print("✅ Script added: \(loadedScript.name)")

                // Refresh view
                selectionManager.objectWillChange.send()
                showStatus("Queued script link to \(targetEntityName) (see Console)")
            } catch {
                print("❌ Failed to load script: \(error.localizedDescription)")
            }
        }
        // Handle Scene files (json)
        else if asset.category == AssetCategory.scenes.rawValue,
                withExtension.lowercased() == "json"
        {
            // Show confirmation dialog before loading scene
            pendingSceneToLoad = asset.path
            showSceneLoadConfirmation = true
            editorController?.currentSceneURL = asset.path
        }
        // Handle HDR files (hdr)
        else if asset.category == AssetCategory.hdr.rawValue,
                withExtension.lowercased() == "hdr"
        {
            // Verify HDR file exists before attempting to load
            guard FileManager.default.fileExists(atPath: asset.path.path) else {
                Logger.log(message: "⚠️ HDR file not found: \(asset.path.path)")
                showStatus("HDR file not found", isError: true)
                return
            }

            // Load HDR as environment IBL
            let filename = asset.path.lastPathComponent
            let directoryURL = asset.path.deletingLastPathComponent()
            generateHDR(filename, from: directoryURL)

            // Only enable IBL if HDR was successfully loaded
            if iblSuccessful {
                applyIBL = true
                print("✅ HDR environment loaded and IBL enabled: \(filename)")
                showStatus("HDR loaded and IBL enabled: \(filename)")
            } else {
                print("⚠️ Failed to load HDR: \(filename)")
                showStatus("Failed to load HDR: \(filename)", isError: true)
            }
        }
    }

    private func updateTargetEntityName(for entityId: EntityID?) {
        guard let entityId, entityId != .invalid else {
            targetEntityName = "None"
            return
        }
        let name = getEntityName(entityId: entityId)
        targetEntityName = name.isEmpty ? "Entity \(entityId)" : name
    }

    // MARK: - Load Scene Helper

    private func loadScene(from url: URL) {
        guard let sceneData = loadGameScene(from: url) else {
            print("❌ Failed to load scene from \(url.lastPathComponent)")
            return
        }

        // Clear current scene
        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()

        // Load new scene
        deserializeScene(sceneData: sceneData)

        // Reset editor state
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false

        // Refresh UI
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()

        // Reset camera
        CameraSystem.shared.activeCamera = findSceneCamera()

        editorController?.currentSceneURL = url
        print("✅ Scene loaded: \(url.lastPathComponent)")
    }
}
