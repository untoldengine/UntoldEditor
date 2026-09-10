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
import UntoldEngine

let runtimeAssetExtension = "untold"
let runtimeModelAssetExtensions: Set<String> = [runtimeAssetExtension, "untoldpack"]
private let runtimeAnimationAssetExtensions: Set<String> = [runtimeAssetExtension, "untoldanim"]
private let allRuntimeAssetExtensions = runtimeModelAssetExtensions.union(runtimeAnimationAssetExtensions)
private let runtimeTextureFolderNames = ["Textures", "textures"]
private let sourceAssetExtensions: Set<String> = ["usd", "usda", "usdc", "usdz", "blend"]
private let streamModelResourceFolderNames = ["tile_exports", "tile_export", "Textures", "textures"]
private let materialTextureExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff"]

struct RuntimeExportRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    let category: AssetCategory
    let destinationFolder: URL
    let outputURL: URL
}

struct TilesExportRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    let destinationFolder: URL
    let outputDirURL: URL
}

func copyRuntimeAssetSidecars(for sourceURL: URL, to destinationFolder: URL, fileManager fm: FileManager = .default) throws {
    let sourceFolder = sourceURL.deletingLastPathComponent()

    for folderName in runtimeTextureFolderNames {
        let textureFolderSource = sourceFolder.appendingPathComponent(folderName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: textureFolderSource.path, isDirectory: &isDir), isDir.boolValue else {
            continue
        }

        let textureFolderDest = destinationFolder.appendingPathComponent(folderName, isDirectory: true)
        if fm.fileExists(atPath: textureFolderDest.path) {
            try fm.removeItem(at: textureFolderDest)
        }
        try fm.copyItem(at: textureFolderSource, to: textureFolderDest)
        return
    }
}

func copyUntoldPackResources(for sourceURL: URL, to destinationFolder: URL, fileManager fm: FileManager = .default) throws {
    guard sourceURL.pathExtension.lowercased() == "untoldpack",
          let pack = loadUntoldPack(url: sourceURL)
    else {
        return
    }

    let sourceFolder = sourceURL.deletingLastPathComponent()
    var copiedRelativeParents: Set<String> = []

    for model in pack.models {
        let relativePath = model.path
        guard relativePath.isEmpty == false,
              relativePath.split(separator: "/").contains("..") == false,
              relativePath.hasPrefix("/") == false
        else {
            continue
        }

        let relativeParent = (relativePath as NSString).deletingLastPathComponent
        let normalizedParent = relativeParent == "." ? "" : relativeParent

        if normalizedParent.isEmpty == false {
            guard copiedRelativeParents.insert(normalizedParent).inserted else {
                continue
            }

            let sourceResourceFolder = sourceFolder.appendingPathComponent(normalizedParent, isDirectory: true)
            let destinationResourceFolder = destinationFolder.appendingPathComponent(normalizedParent, isDirectory: true)
            if fm.fileExists(atPath: destinationResourceFolder.path) {
                try fm.removeItem(at: destinationResourceFolder)
            }
            try fm.createDirectory(at: destinationResourceFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sourceResourceFolder, to: destinationResourceFolder)
        } else {
            let sourceResource = sourceFolder.appendingPathComponent(relativePath)
            let destinationResource = destinationFolder.appendingPathComponent(relativePath)
            if fm.fileExists(atPath: destinationResource.path) {
                try fm.removeItem(at: destinationResource)
            }
            try fm.createDirectory(at: destinationResource.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: sourceResource, to: destinationResource)
        }
    }
}

/// Importing a source asset (USD, .blend, …) means two things: the file is copied into
/// the project, and then it is converted to the engine's runtime format. This does the
/// first part. The source lands in `destinationFolder` (next to where the converter will
/// write its output) together with any sibling texture folder, so the project keeps the
/// original even if only the cooked file is ever used, and it can be re-converted later
/// without the file it came from. Returns the project copy, which is what converters
/// should run on. A source that already lives in `destinationFolder` is left alone.
func importSourceAsset(
    sourceURL: URL,
    destinationFolder: URL,
    fileManager fm: FileManager = .default,
    copy: ((URL, URL) throws -> Void)? = nil
) throws -> URL {
    let copyFile = copy ?? { try fm.copyItem(at: $0, to: $1) }
    try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    let destinationURL = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
    if destinationURL.standardizedFileURL.path == sourceURL.standardizedFileURL.path {
        return sourceURL
    }
    if fm.fileExists(atPath: destinationURL.path) {
        try fm.removeItem(at: destinationURL)
    }
    try copyFile(sourceURL, destinationURL)
    try copyRuntimeAssetSidecars(for: sourceURL, to: destinationFolder, fileManager: fm)
    return destinationURL
}

func runtimeAssetExtensions(for category: AssetCategory) -> Set<String> {
    switch category {
    case .models:
        return runtimeModelAssetExtensions
    case .animations:
        return runtimeAnimationAssetExtensions
    default:
        return []
    }
}

func runtimeAssetFilenameForLoading(_ url: URL) -> String {
    url.deletingPathExtension().path
}

private func runtimeAssetExtensionPriority(_ ext: String) -> Int {
    switch ext.lowercased() {
    case "untoldpack", "untoldanim":
        return 0
    case runtimeAssetExtension:
        return 1
    default:
        return 2
    }
}

func primaryRuntimeAsset(
    in folder: URL,
    allowedExtensions: Set<String> = runtimeModelAssetExtensions,
    fileManager fm: FileManager = .default
) -> URL? {
    guard let contents = try? fm.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let runtimeAssets = contents
        .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted {
            let lhsPriority = runtimeAssetExtensionPriority($0.pathExtension)
            let rhsPriority = runtimeAssetExtensionPriority($1.pathExtension)
            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }
            return $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

    let folderName = folder.lastPathComponent
    return runtimeAssets.first { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }
        ?? (runtimeAssets.count == 1 ? runtimeAssets.first : nil)
}

func isTiledSceneManifest(_ url: URL) -> Bool {
    guard url.pathExtension.lowercased() == "json",
          let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          object["streaming_defaults"] != nil,
          let tiles = object["tiles"] as? [[String: Any]]
    else {
        return false
    }

    return tiles.contains { tile in
        guard let path = tile["path_relative_to_manifest"] as? String else { return false }
        return path.isEmpty == false
    }
}

func primaryTiledSceneManifest(in folder: URL, fileManager fm: FileManager = .default) -> URL? {
    guard let contents = try? fm.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let manifests = contents
        .filter { isTiledSceneManifest($0) }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

    let folderName = folder.lastPathComponent
    return manifests.first { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }
        ?? (manifests.count == 1 ? manifests.first : nil)
}

func tiledSceneResourceNames(in manifestURL: URL) -> Set<String> {
    guard let data = try? Data(contentsOf: manifestURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return []
    }

    var resourceNames = Set<String>()

    func collectResourceName(from path: String?) {
        guard let path,
              path.isEmpty == false,
              path.hasPrefix("/") == false,
              URL(string: path)?.scheme == nil
        else {
            return
        }

        let firstComponent = path.split(separator: "/").first.map(String.init)
        if let firstComponent, firstComponent.isEmpty == false {
            resourceNames.insert(firstComponent)
        }
    }

    if let tiles = object["tiles"] as? [[String: Any]] {
        for tile in tiles {
            collectResourceName(from: tile["path_relative_to_manifest"] as? String)

            if let hlodLevels = tile["hlod_levels"] as? [[String: Any]] {
                for level in hlodLevels {
                    collectResourceName(from: level["path"] as? String)
                }
            }

            if let lodLevels = tile["lod_levels"] as? [[String: Any]] {
                for level in lodLevels {
                    collectResourceName(from: level["path"] as? String)
                }
            }
        }
    }

    if let sharedBucket = object["shared_bucket"] as? [String: Any] {
        collectResourceName(from: sharedBucket["path_relative_to_manifest"] as? String)
    }

    return resourceNames
}

func importStreamModelManifest(sourceURL: URL, destinationFolder: URL, fileManager fm: FileManager = .default) throws {
    try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    let destinationManifest = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
    if fm.fileExists(atPath: destinationManifest.path) {
        try fm.removeItem(at: destinationManifest)
    }
    try fm.copyItem(at: sourceURL, to: destinationManifest)

    let sourceFolder = sourceURL.deletingLastPathComponent()
    var resourceNames = tiledSceneResourceNames(in: sourceURL)
    if resourceNames.isEmpty {
        resourceNames.formUnion(streamModelResourceFolderNames)
    }

    for resourceName in resourceNames {
        let sourceResource = sourceFolder.appendingPathComponent(resourceName)
        guard fm.fileExists(atPath: sourceResource.path) else { continue }

        let destinationResource = destinationFolder.appendingPathComponent(resourceName)
        if fm.fileExists(atPath: destinationResource.path) {
            try fm.removeItem(at: destinationResource)
        }
        try fm.copyItem(at: sourceResource, to: destinationResource)
    }
}

func findUntoldEngineScript(named name: String, fileManager fm: FileManager = .default) -> URL? {
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)

    var scriptsDirCandidates: [URL] = []

    // DMG / installed app: scripts are bundled in Contents/Resources/scripts/
    if let resourceURL = Bundle.main.resourceURL {
        scriptsDirCandidates.append(resourceURL.appendingPathComponent("scripts").standardizedFileURL)
    }

    scriptsDirCandidates += [
        // `swift run` from the package root: cwd is the package root
        cwd.appendingPathComponent(".build/checkouts/UntoldEngine/scripts").standardizedFileURL,
        // Local package override (Package.swift uses path: "../UntoldEngine")
        cwd.appendingPathComponent("../UntoldEngine/scripts").standardizedFileURL,
    ]

    if let execURL = Bundle.main.executableURL {
        // SPM CLI build: executable is at .build/<arch>/<config>/<name>
        // Three levels up lands at .build/
        let spmBuildDir = execURL
            .deletingLastPathComponent() // <config>/
            .deletingLastPathComponent() // <arch>/
            .deletingLastPathComponent() // .build/
        scriptsDirCandidates.append(
            spmBuildDir.appendingPathComponent("checkouts/UntoldEngine/scripts").standardizedFileURL
        )

        // Xcode build: executable is at DerivedData/<hash>/Build/Products/<config>/<name>
        // Four levels up lands at DerivedData/<hash>/
        let derivedDataDir = execURL
            .deletingLastPathComponent() // <config>/
            .deletingLastPathComponent() // Products/
            .deletingLastPathComponent() // Build/
            .deletingLastPathComponent() // DerivedData/<hash>/
        scriptsDirCandidates.append(
            derivedDataDir.appendingPathComponent("SourcePackages/checkouts/UntoldEngine/scripts").standardizedFileURL
        )
    }

    return scriptsDirCandidates
        .map { $0.appendingPathComponent(name) }
        .first { fm.isExecutableFile(atPath: $0.path) || fm.fileExists(atPath: $0.path) }
}

func findExportUntoldScript(fileManager fm: FileManager = .default) -> URL? {
    findUntoldEngineScript(named: "export-untold", fileManager: fm)
}

func findExportUntoldTilesScript(fileManager fm: FileManager = .default) -> URL? {
    findUntoldEngineScript(named: "export-untold-tiles", fileManager: fm)
}

func findTexbakeScript(fileManager fm: FileManager = .default) -> URL? {
    findUntoldEngineScript(named: "texbake.py", fileManager: fm)
}

/// Runs `python3 <script> <arguments>` synchronously on the calling thread.
/// Returns the termination status plus captured stdout and stderr.
/// Pass a non-empty `astcencBin` to set `ASTCENC_BIN` in the process environment.
func runTexbakeStep(script: URL, arguments: [String], astcencBin: String = "") -> (status: Int32, stdout: String, stderr: String) {
    let tempDir = FileManager.default.temporaryDirectory
    let outURL = tempDir.appendingPathComponent("texbake-\(UUID().uuidString).out")
    let errURL = tempDir.appendingPathComponent("texbake-\(UUID().uuidString).err")
    defer {
        try? FileManager.default.removeItem(at: outURL)
        try? FileManager.default.removeItem(at: errURL)
    }
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    FileManager.default.createFile(atPath: errURL.path, contents: nil)
    guard let outHandle = try? FileHandle(forWritingTo: outURL),
          let errHandle = try? FileHandle(forWritingTo: errURL)
    else {
        return (-1, "", "Failed to open log file handles")
    }
    defer {
        try? outHandle.close()
        try? errHandle.close()
    }
    // Run through the user's login shell so ~/.zprofile / ~/.bash_profile are
    // sourced and the correct python3 (with Pillow, lz4, etc.) is on PATH.
    let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    let quotedArgs = ([script.path] + arguments)
        .map { "'\($0.replacingOccurrences(of: "'", with: "'\\''"))'" }
        .joined(separator: " ")
    let astcencPrefix = astcencBin.isEmpty ? "" : "ASTCENC_BIN='\(astcencBin)' "
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-l", "-c", "\(astcencPrefix)python3 \(quotedArgs)"]
    process.standardOutput = outHandle
    process.standardError = errHandle
    guard (try? process.run()) != nil else {
        return (-1, "", "Failed to launch texbake.py")
    }
    process.waitUntilExit()
    let stdout = (try? String(contentsOf: outURL, encoding: .utf8)) ?? ""
    let stderr = (try? String(contentsOf: errURL, encoding: .utf8)) ?? ""
    return (process.terminationStatus, stdout, stderr)
}

enum AssetCategory: String, CaseIterable {
    case models = "Models"
    case streamModels = "StreamModels"
    case animations = "Animations"
    case scripts = "Scripts"
    case scenes = "Scenes"
    case gaussians = "Gaussians"
    case materials = "Materials"
    case hdr = "HDR"
    case lut = "LUT"

    var displayName: String {
        switch self {
        case .streamModels:
            return "Stream Models"
        default:
            return rawValue
        }
    }

    var iconName: String {
        switch self {
        case .models:
            return "cube.fill"
        case .animations:
            return "film"
        case .streamModels:
            return "square.stack.3d.up.fill"
        case .hdr:
            return "film"
        case .lut:
            return "camera.filters"
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

func editorTextureType(from filename: String) -> TextureType? {
    let lowercasedName = filename.lowercased()

    if lowercasedName.contains("basecolor")
        || lowercasedName.contains("base_color")
        || lowercasedName.contains("albedo")
        || lowercasedName.contains("diffuse")
        || lowercasedName.contains("color")
    {
        return .baseColor
    } else if lowercasedName.contains("roughness") || lowercasedName.contains("rough") {
        return .roughness
    } else if lowercasedName.contains("metallic") || lowercasedName.contains("metalness") || lowercasedName.contains("metal") {
        return .metallic
    } else if lowercasedName.contains("normalgx")
        || lowercasedName.contains("normaldx")
        || lowercasedName.contains("normalgl")
        || lowercasedName.contains("normal")
        || lowercasedName.contains("nrm")
    {
        return .normal
    } else if lowercasedName.contains("height")
        || lowercasedName.contains("displacement")
        || lowercasedName.contains("displace")
        || lowercasedName.contains("bump")
    {
        return .height
    }

    return nil
}

func editorMaterialTextureAssignments(in folder: URL, fileManager: FileManager = .default) -> [TextureType: URL] {
    guard let enumerator = fileManager.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return [:]
    }

    let textureURLs = enumerator.compactMap { item -> URL? in
        guard let url = item as? URL else { return nil }
        guard materialTextureExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return url
    }

    var assignments: [TextureType: URL] = [:]
    for url in textureURLs.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
        guard let textureType = editorTextureType(from: url.deletingPathExtension().lastPathComponent),
              assignments[textureType] == nil
        else {
            continue
        }
        assignments[textureType] = url
    }

    return assignments
}

private struct RemoteStreamImportSheet: View {
    @Binding var urlString: String
    var onImport: () -> Void
    var onCancel: () -> Void

    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Remote Stream")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Manifest URL")
                    .font(.system(size: 12))
                    .foregroundColor(.editorTextSecondary)
                TextField("https://cdn.example.com/dungeon/dungeon.json", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isURLFocused)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Import", action: onImport)
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { isURLFocused = true }
    }
}

/// Click handling for a content browser row. A file row selects on the very
/// first click: its double-click is a simultaneous gesture, so SwiftUI does not
/// hold the single click back until the double-click interval has passed (the
/// sequential `onTapGesture(count: 2)` then `onTapGesture(count: 1)` pair does,
/// which reads as a laggy selection). On a double-click the row is selected
/// twice, harmlessly, and then placed. A folder row keeps the sequential pair:
/// its single click navigates into the folder, which would otherwise fire
/// before the double-click that places the folder's primary asset.
struct AssetRowClickGestures: ViewModifier {
    let isFolder: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        if isFolder {
            content
                .onTapGesture(count: 2, perform: onDoubleClick)
                .onTapGesture(count: 1, perform: onClick)
        } else {
            content
                .onTapGesture(perform: onClick)
                .simultaneousGesture(TapGesture(count: 2).onEnded(onDoubleClick))
        }
    }
}

struct AssetBrowserView: View {
    @Binding var assets: [String: [Asset]]
    @Binding var selectedAsset: Asset?
    /// Navigation lives outside the view so it survives the browser being
    /// removed from the hierarchy (e.g. while the Console tab is showing).
    @ObservedObject var navigation = AssetBrowserNavigationState()
    @ObservedObject var editorBaseAssetPath = EditorAssetBasePath.shared
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel

    private var selectedCategory: String? {
        get { navigation.selectedCategory }
        nonmutating set { navigation.selectedCategory = newValue }
    }

    private var selectedAssetName: String? {
        get { navigation.selectedAssetName }
        nonmutating set { navigation.selectedAssetName = newValue }
    }

    private var folderPathStack: [URL] {
        get { navigation.folderPathStack }
        nonmutating set { navigation.folderPathStack = newValue }
    }

    private var expandedDirs: Set<URL> {
        get { navigation.expandedDirs }
        nonmutating set { navigation.expandedDirs = newValue }
    }

    private var selectedDirURL: URL? {
        get { navigation.selectedDirURL }
        nonmutating set { navigation.selectedDirURL = newValue }
    }

    private var rootExpanded: Bool {
        get { navigation.rootExpanded }
        nonmutating set { navigation.rootExpanded = newValue }
    }

    @State private var showSceneLoadConfirmation = false
    @State private var pendingSceneToLoad: URL?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteAsset: Asset?
    @State private var showBasePathAlert = false
    @Binding var searchQuery: String
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var targetEntityName: String = "None"
    @State private var showImportMenu = false
    @State private var showRemoteStreamSheet = false
    @State private var remoteStreamURLString = ""
    /// The cook sheet's item: the `.ply` of the row whose "Cook to .untoldgs…" was chosen.
    /// Presented with `.sheet(item:)`, so the sheet exists only while there is a request,
    /// and a request always carries sources (`GaussianCookRequest.init?(sources:)`).
    @State private var pendingGaussianCook: GaussianCookRequest?
    @State private var gaussianCookSettings = GaussianCookSettings()
    /// Import copies still running (see `AssetImportCopy.swift`). Past the placeholder
    /// delay each one is drawn as a placeholder row in the folder that will receive it.
    @State private var pendingImports: [PendingAssetImport] = []
    @State private var pendingRuntimeExport: RuntimeExportRequest?
    @State private var runtimeExportQueue: [RuntimeExportRequest] = []
    @State private var isExportingRuntimeAsset = false
    /// Requests confirmed via "Cook" while another export was already running;
    /// drained one at a time by finishRuntimeExport().
    @State private var runtimeExportWorkQueue: [RuntimeExportRequest] = []
    @State private var exportConvertOrientation = true
    @State private var exportSourceOrientation = "blender-native"
    @State private var pendingTilesExport: TilesExportRequest?
    @State private var tilesExportQueue: [TilesExportRequest] = []
    @State private var isExportingTilesAsset = false
    /// Same as runtimeExportWorkQueue, for tiled stream-model exports.
    @State private var tilesExportWorkQueue: [TilesExportRequest] = []
    @State private var exportTileSizeX: String = "25"
    @State private var exportTileSizeY: String = "10000"
    @State private var exportTileSizeZ: String = "25"
    @State private var exportCompressGeometry = false
    @State private var exportCompressTextures = false
    @State private var astcencBinPath: String = ""
    @State private var exportQuadTree = false
    @State private var exportAutoTileSize = false
    @State private var exportGenerateHLOD = false
    @State private var exportGenerateLOD = false
    @State private var exportDryRun = false
    var editor_addEntityWithAsset: () -> Void
    var editor_loadSceneAuthoredFromAsset: (Asset) -> Void = { _ in }
    private var currentFolderPath: URL? {
        folderPathStack.last
    }

    // MARK: - Finder helpers

    private func categoryRootURL(_ category: AssetCategory) -> URL? {
        assetBasePath?.appendingPathComponent(category.rawValue, isDirectory: true)
    }

    /// Root-level folders the user created that aren't one of the fixed categories.
    private var customRootFolders: [URL] {
        guard let root = assetBasePath else { return [] }
        let categoryNames = Set(AssetCategory.allCases.map(\.rawValue))
        return subdirectories(of: root).filter { !categoryNames.contains($0.lastPathComponent) }
    }

    /// The directory currently shown on the right: a generic (non-category)
    /// selection wins, otherwise the open subfolder, otherwise the selected
    /// category's root folder.
    private var currentDirectoryURL: URL? {
        if let generic = selectedDirURL {
            return generic
        }
        if let folder = currentFolderPath {
            return folder
        }
        guard let raw = selectedCategory, let category = AssetCategory(rawValue: raw) else { return nil }
        return categoryRootURL(category)
    }

    /// Category owning `url` (matched by the top-level folder under the asset
    /// root), used to pick import file types for generic folders.
    private func inferCategory(for url: URL?) -> AssetCategory? {
        guard let url, let root = assetBasePath?.standardizedFileURL else { return nil }
        let rootComponents = root.pathComponents
        let comps = url.standardizedFileURL.pathComponents
        guard comps.count > rootComponents.count else { return nil }
        let top = comps[rootComponents.count]
        return AssetCategory(rawValue: top)
    }

    private func subdirectories(of url: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func toggleDir(_ url: URL) {
        if expandedDirs.contains(url) {
            expandedDirs.remove(url)
        } else {
            expandedDirs.insert(url)
        }
    }

    private func isDirectorySelected(url: URL, category: String) -> Bool {
        guard selectedDirURL == nil else { return false }
        guard selectedCategory == category else { return false }
        guard let current = currentDirectoryURL else { return false }
        return current.standardizedFileURL == url.standardizedFileURL
    }

    private func selectDirectory(url: URL, category: String) {
        navigation.lightsSelected = false
        navigation.primitivesSelected = false
        selectedDirURL = nil
        selectedCategory = category
        selectedAsset = nil
        selectedAssetName = nil

        guard let cat = AssetCategory(rawValue: category), let root = categoryRootURL(cat),
              url.standardizedFileURL != root.standardizedFileURL
        else {
            folderPathStack = []
            return
        }

        // Build the folder chain from the category root down to `url`.
        let rootComponents = root.standardizedFileURL.pathComponents
        let relative = Array(url.standardizedFileURL.pathComponents.dropFirst(rootComponents.count))
        var stack: [URL] = []
        var cursor = root
        for component in relative {
            cursor = cursor.appendingPathComponent(component, isDirectory: true)
            stack.append(cursor)
        }
        folderPathStack = stack
    }

    /// Entry point for the "New Directory" menu items. If there's no project
    /// asset folder yet, tell the user instead of silently doing nothing.
    private func requestNewDirectory(in parent: URL?) {
        guard let parent else {
            showBasePathAlert = true
            return
        }
        createFolder(in: parent)
    }

    /// Create a uniquely-named subfolder inside `parent` (creating `parent` if
    /// needed, e.g. an empty category root) and reveal it.
    private func createFolder(in parent: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)

        var name = "New Folder"
        var index = 1
        var dest = parent.appendingPathComponent(name, isDirectory: true)
        while fm.fileExists(atPath: dest.path) {
            index += 1
            name = "New Folder \(index)"
            dest = parent.appendingPathComponent(name, isDirectory: true)
        }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        expandedDirs.insert(parent)
        loadAssets()
    }

    private func importIntoCurrentDirectory() {
        let category = selectedCategory.flatMap { AssetCategory(rawValue: $0) }
            ?? inferCategory(for: currentDirectoryURL)
            ?? .models
        importAssetForCategory(category, into: currentDirectoryURL)
    }

    /// Returns AnyView (not `some View`) so the recursive child call is allowed.
    /// `category == nil` marks a generic (non-category) folder such as the root
    /// or a custom directory created at root level. `url` may be nil for a
    /// category root when no project folder is set yet.
    /// Fixed left-tree entry for the Lights shelf: not backed by disk, so it has no
    /// children and doesn't participate in the directory/category selection state
    /// beyond the `lightsSelected` flag.
    private var lightsCategoryRow: some View {
        let isSelected = navigation.lightsSelected
        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.clear)
                .frame(width: 10)

            Image(systemName: isSelected ? "lightbulb.fill" : "lightbulb")
                .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
            Text("Lights")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, 12)
        .background(isSelected ? Color.editorAccentSoft : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.lightsSelected = true
            navigation.primitivesSelected = false
            selectedDirURL = nil
            selectedCategory = nil
            folderPathStack = []
            selectedAsset = nil
            selectedAssetName = nil
        }
    }

    /// Row for one light type: drags into the viewport or the hierarchy the same
    /// way an asset browser row does (see `placeLight` in AssetPlacement.swift),
    /// or places it at the origin on a double-click.
    private func lightRow(_ kind: PlaceableLightType) -> some View {
        HStack {
            Image(systemName: kind.iconName)
                .foregroundColor(.editorTextTertiary)
            Text(kind.displayName)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(LightDragPayload(lightType: kind))
        .onTapGesture(count: 2) {
            let placement = placeLight(kind, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
        }
    }

    private var lightsShelfView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PlaceableLightType.allCases, id: \.self) { kind in
                lightRow(kind)
            }
        }
    }

    /// Fixed left-tree entry for the Primitives shelf, mirroring `lightsCategoryRow`.
    private var primitivesCategoryRow: some View {
        let isSelected = navigation.primitivesSelected
        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.clear)
                .frame(width: 10)

            Image(systemName: isSelected ? "cube.fill" : "cube")
                .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
            Text("Primitives")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, 12)
        .background(isSelected ? Color.editorAccentSoft : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.primitivesSelected = true
            navigation.lightsSelected = false
            selectedDirURL = nil
            selectedCategory = nil
            folderPathStack = []
            selectedAsset = nil
            selectedAssetName = nil
        }
    }

    /// Row for one primitive: drags into the viewport or the hierarchy the same way
    /// an asset browser row does (see `placePrimitive` in AssetPlacement.swift), or
    /// places it at the origin on a double-click.
    private func primitiveRow(_ kind: PlaceablePrimitiveType) -> some View {
        HStack {
            Image(systemName: kind.iconName)
                .foregroundColor(.editorTextTertiary)
            Text(kind.displayName)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(PrimitiveDragPayload(primitiveType: kind))
        .onTapGesture(count: 2) {
            let placement = placePrimitive(kind, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
        }
    }

    private var primitivesShelfView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PlaceablePrimitiveType.allCases, id: \.self) { kind in
                primitiveRow(kind)
            }
        }
    }

    private func directoryNode(url: URL?, name: String, category: String?, depth: Int) -> AnyView {
        let isGeneric = (category == nil)
        let subfolders: [URL] = {
            guard let url else { return [] }
            if category == AssetCategory.scripts.rawValue {
                return []
            }
            return subdirectories(of: url)
        }()
        let hasChildren = !subfolders.isEmpty
        let isExpanded = url.map { expandedDirs.contains($0) } ?? false
        let isSelected: Bool = {
            if isGeneric {
                guard let url, let sel = selectedDirURL else { return false }
                return sel.standardizedFileURL == url.standardizedFileURL
            }
            if let url {
                return isDirectorySelected(url: url, category: category!)
            }
            return selectedDirURL == nil && selectedCategory == category && folderPathStack.isEmpty
        }()

        return AnyView(
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Button(action: {
                        if let url {
                            toggleDir(url)
                        }
                    }) {
                        Image(systemName: hasChildren ? (isExpanded ? "chevron.down" : "chevron.right") : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(hasChildren ? .editorTextSecondary : .clear)
                            .frame(width: 10)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(!hasChildren)

                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
                    Text(name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.editorTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .padding(.leading, CGFloat(depth) * 12)
                .background(isSelected ? Color.editorAccentSoft : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture {
                    navigation.lightsSelected = false
                    navigation.primitivesSelected = false
                    if isGeneric {
                        if let url {
                            selectedDirURL = url
                            selectedCategory = nil
                            folderPathStack = []
                            selectedAsset = nil
                            selectedAssetName = nil
                        }
                    } else if let url {
                        selectDirectory(url: url, category: category!)
                    } else {
                        selectedDirURL = nil
                        selectedCategory = category
                        folderPathStack = []
                        selectedAsset = nil
                        selectedAssetName = nil
                    }
                }
                .contextMenu {
                    Button {
                        requestNewDirectory(in: url)
                    } label: {
                        Label("New Directory", systemImage: "folder.badge.plus")
                    }
                }

                if isExpanded {
                    ForEach(subfolders, id: \.self) { sub in
                        directoryNode(url: sub, name: sub.lastPathComponent, category: category, depth: depth + 1)
                    }
                }
            }
        )
    }

    /// Root node of the directory tree (the project's asset folder). Right-click
    /// to create a directory at root level.
    private var rootDirectoryRow: some View {
        let root = assetBasePath
        let isSelected = root.map { r in selectedDirURL?.standardizedFileURL == r.standardizedFileURL } ?? false
        return HStack(spacing: 6) {
            Button(action: { rootExpanded.toggle() }) {
                Image(systemName: rootExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.editorTextSecondary)
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
            .focusable(false)

            Image(systemName: "folder.fill")
                .foregroundColor(isSelected ? Color.editorAccent : .editorAccent)
            Text(editorBaseAssetPath.projectName ?? "Assets")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(isSelected ? Color.editorAccentSoft : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let root {
                navigation.lightsSelected = false
                navigation.primitivesSelected = false
                selectedDirURL = root
                selectedCategory = nil
                folderPathStack = []
                selectedAsset = nil
                selectedAssetName = nil
            }
        }
        .contextMenu {
            Button {
                requestNewDirectory(in: root)
            } label: {
                Label("New Directory", systemImage: "folder.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var rightPaneContents: some View {
        if navigation.lightsSelected {
            lightsShelfView
        } else if navigation.primitivesSelected {
            primitivesShelfView
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

    private func importAssetForCategory(_ category: AssetCategory, into destinationOverride: URL? = nil) {
        guard editorBaseAssetPath.basePath != nil else {
            showBasePathAlert = true
            return
        }

        let openPanel = NSOpenPanel()

        // Set allowed file types based on category
        switch category {
        case .models:
            openPanel.allowedContentTypes = (runtimeModelAssetExtensions.sorted() + sourceAssetExtensions.sorted()).compactMap {
                UTType(filenameExtension: $0)
            }
        case .animations:
            openPanel.allowedContentTypes = (runtimeAnimationAssetExtensions.sorted() + sourceAssetExtensions.sorted()).compactMap {
                UTType(filenameExtension: $0)
            }
        case .streamModels:
            openPanel.allowedContentTypes = ([UTType(filenameExtension: "json")!] + sourceAssetExtensions.sorted().compactMap { UTType(filenameExtension: $0) })
        case .scripts:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "uscript")!]
        case .scenes:
            openPanel.allowedContentTypes = [.untoldScene]
        case .gaussians:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "ply")!, UTType(filenameExtension: "untoldgs")!]
        case .materials:
            openPanel.allowedContentTypes = [.png, .jpeg, .tiff]
        case .hdr:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "hdr")!, UTType(filenameExtension: "exr")!]
        case .lut:
            openPanel.allowedContentTypes = [UTType(filenameExtension: "cube")!]
        }

        openPanel.canChooseDirectories = (category == .materials || category == .streamModels || category == .gaussians)
        openPanel.allowsMultipleSelection = true

        guard let basePath = assetBasePath else { return }
        let categoryString = category.rawValue
        // Ensure category is valid
        guard AssetCategory.allCases.map(\.rawValue).contains(categoryString) else { return }

        let fm = FileManager.default
        // Import into the folder the user has open (Finder-style), falling back
        // to the category root.
        let categoryRoot = destinationOverride ?? basePath.appendingPathComponent(categoryString, isDirectory: true)
        // Ensure the destination folder exists (e.g., <Base>/Models or a subfolder)
        try? fm.createDirectory(at: categoryRoot, withIntermediateDirectories: true)

        guard openPanel.runModal() == .OK else { return }

        // Every copy is its own Tasks-panel job on the import queue; the batch group
        // fires once they have all landed (or failed).
        let batch = DispatchGroup()

        for sourceURL in openPanel.urls {
            switch categoryString {
            case "HDR", "LUT", "Scenes", "Scripts":
                // Plain copy into the folder
                let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent)
                enqueueImport(destination: destURL, isFolder: false, batch: batch) { ctx in
                    try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                }

            case "Gaussians":
                if sourceURL.hasDirectoryPath {
                    guard primaryGaussianAsset(in: sourceURL, fileManager: fm) != nil else {
                        showStatus("No Gaussian asset found in selected folder", isError: true)
                        continue
                    }

                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    // Gaussian files are imported as a folder package so progressive tiers stay grouped.
                    let destFolder = gaussianPackageFolder(for: sourceURL, in: categoryRoot)
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importGaussianAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                }

            case "Materials":
                if sourceURL.hasDirectoryPath {
                    // Copy entire material folder (recommended)
                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    // Single texture fallback → folder named after the file (without ext)
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let materialFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    enqueueImport(destination: materialFolder, isFolder: true, batch: batch) { ctx in
                        try fm.createDirectory(at: ctx.stagingURL, withIntermediateDirectories: true)
                        try ctx.copy(sourceURL, to: ctx.stagingURL.appendingPathComponent(sourceURL.lastPathComponent), fileManager: fm)
                    }
                }

            case "Models", "Animations":
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                let sourceExtension = sourceURL.pathExtension.lowercased()

                if runtimeAssetExtensions(for: category).contains(sourceExtension) {
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        try importRuntimeAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                } else if sourceAssetExtensions.contains(sourceExtension) {
                    // Import = copy the source into the project. Cooking to .untold /
                    // .untoldpack happens when the user asks for it, from the row's
                    // "Cook to .untold…" context action (same pattern as Gaussians).
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importSourceAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                }

            case "StreamModels":
                let sourceExtension = sourceURL.pathExtension.lowercased()
                if sourceAssetExtensions.contains(sourceExtension) {
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    // Same as Models: keep the source in the project. Tiling happens
                    // when the user asks for it, from the row's "Cook to tiled
                    // stream model…" context action.
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        _ = try importSourceAsset(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm) {
                            try ctx.copy($0, to: $1, fileManager: fm)
                        }
                    }
                } else if sourceURL.hasDirectoryPath {
                    guard primaryTiledSceneManifest(in: sourceURL, fileManager: fm) != nil else {
                        showStatus("No tiled scene manifest found in selected folder", isError: true)
                        continue
                    }

                    let destURL = categoryRoot.appendingPathComponent(sourceURL.lastPathComponent, isDirectory: true)
                    enqueueImport(destination: destURL, isFolder: true, batch: batch) { ctx in
                        try ctx.copy(sourceURL, to: ctx.stagingURL, fileManager: fm)
                    }
                } else if isTiledSceneManifest(sourceURL) {
                    let baseName = sourceURL.deletingPathExtension().lastPathComponent
                    let destFolder = categoryRoot.appendingPathComponent(baseName, isDirectory: true)
                    enqueueImport(destination: destFolder, isFolder: true, batch: batch) { ctx in
                        try fm.createDirectory(at: ctx.stagingURL, withIntermediateDirectories: true)
                        try importStreamModelManifest(sourceURL: sourceURL, destinationFolder: ctx.stagingURL, fileManager: fm)
                    }
                } else {
                    showStatus("Selected JSON is not a tiled scene manifest", isError: true)
                }

            default:
                break
            }
        }

        let count = openPanel.urls.count
        showStatus("Importing \(count) item(s) (see Tasks)...")

        batch.notify(queue: .main) {
            loadAssets()
            if runtimeExportQueue.isEmpty, pendingRuntimeExport == nil,
               tilesExportQueue.isEmpty, pendingTilesExport == nil
            {
                showStatus("Imported \(count) item(s)")
            }
        }
    }

    /// Copies one imported item as a Tasks-panel job (see `importAssetTracked`). The
    /// item is hidden until the copy is complete; if the copy is still running after
    /// `assetImportPlaceholderDelay` the content panel shows a placeholder row for it
    /// with the copy progress. `completion` runs on the main queue with the final URL
    /// only when the copy worked.
    private func enqueueImport(
        destination: URL,
        isFolder: Bool,
        batch: DispatchGroup,
        work: @escaping (AssetImportContext) throws -> Void,
        completion: @escaping (URL) -> Void = { _ in }
    ) {
        let pending = PendingAssetImport(destinationURL: destination, isFolder: isFolder)
        pendingImports.append(pending)
        batch.enter()

        DispatchQueue.main.asyncAfter(deadline: .now() + assetImportPlaceholderDelay) {
            guard let index = pendingImports.firstIndex(where: { $0.id == pending.id }) else { return }
            pendingImports[index].showsPlaceholder = true
        }

        let detail = assetBasePath.map { base in
            destination.deletingLastPathComponent().path
                .replacingOccurrences(of: base.path, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } ?? ""
        importAssetTracked(
            destination: destination,
            detail: detail.isEmpty ? "" : "→ \(detail)/",
            onProgress: { progress in
                guard let index = pendingImports.firstIndex(where: { $0.id == pending.id }) else { return }
                pendingImports[index].progress = progress
            },
            work: work
        ) { result in
            pendingImports.removeAll { $0.id == pending.id }
            switch result {
            case let .success(url):
                loadAssets()
                completion(url)
            case .failure(is CancellationError):
                showStatus("Import cancelled: \(destination.lastPathComponent)")
            case let .failure(error):
                showStatus("Import failed for \(destination.lastPathComponent): \(error.localizedDescription)", isError: true)
                Logger.log(message: "❌ Import failed for \(destination.lastPathComponent): \(error)")
            }
            batch.leave()
        }
    }

    private func importRuntimeAsset(
        sourceURL: URL,
        destinationFolder: URL,
        fileManager fm: FileManager,
        copy: ((URL, URL) throws -> Void)? = nil
    ) throws {
        let copyFile = copy ?? { try fm.copyItem(at: $0, to: $1) }
        try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let destinationAsset = destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destinationAsset.path) {
            try fm.removeItem(at: destinationAsset)
        }
        try copyFile(sourceURL, destinationAsset)
        try copyRuntimeAssetSidecars(for: sourceURL, to: destinationFolder, fileManager: fm)
        try copyUntoldPackResources(for: sourceURL, to: destinationFolder, fileManager: fm)
    }

    private func queueRuntimeExport(sourceURL: URL, category: AssetCategory, destinationFolder: URL) {
        let outputExtension = category == .animations ? "untoldanim" : runtimeAssetExtension
        let outputURL = destinationFolder
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(outputExtension)
        let request = RuntimeExportRequest(
            sourceURL: sourceURL,
            category: category,
            destinationFolder: destinationFolder,
            outputURL: outputURL
        )

        runtimeExportQueue.append(request)
        presentNextRuntimeExportIfNeeded()
    }

    private func presentNextRuntimeExportIfNeeded() {
        guard pendingRuntimeExport == nil, !runtimeExportQueue.isEmpty else {
            return
        }
        pendingRuntimeExport = runtimeExportQueue.removeFirst()
    }

    private func runtimeExportSheet(for request: RuntimeExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cook to Untold Asset")
                .font(.title2)
                .bold()

            Text("Cook this USD or .blend source into Untold Engine's runtime format to use it in scenes: a single model becomes a .untold file, while a scene with multiple models becomes a .untoldpack bundle (one .untold per model). The source stays next to the output and can be cooked again later.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.top, 6)
                Text(request.outputURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                Text("If the source contains multiple models, a .untoldpack manifest is written here instead.")
                    .font(.caption2)
                    .foregroundColor(.editorTextSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Convert orientation", isOn: $exportConvertOrientation)

                Picker("Source orientation", selection: $exportSourceOrientation) {
                    Text("Blender native").tag("blender-native")
                    Text("Engine oriented").tag("engine-oriented")
                }
                .disabled(!exportConvertOrientation)

                Toggle("Compress geometry (LZ4)", isOn: $exportCompressGeometry)
                    .help("Compresses vertex and index data with LZ4. Requires the Python lz4 package.")
                if exportCompressGeometry {
                    Text("Requires: pip install lz4")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .padding(.leading, 20)
                }

                Toggle("Compress textures (ASTC)", isOn: $exportCompressTextures)
                    .help("Converts textures to GPU-native ASTC format. Requires astcenc and the Python Pillow package.")
                if exportCompressTextures {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Link("Install astcenc →", destination: URL(string: "https://github.com/ARM-software/astc-encoder/releases")!)
                                .font(.caption)
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            Text("Also requires: pip install Pillow")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("astcenc path (optional)")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            HStack {
                                TextField("/opt/homebrew/bin/astcenc", text: $astcencBinPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.title = "Select astcenc binary"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        astcencBinPath = url.path
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingRuntimeExport = nil
                    presentNextRuntimeExportIfNeeded()
                }

                Button("Cook") {
                    pendingRuntimeExport = nil
                    presentNextRuntimeExportIfNeeded()
                    exportRuntimeAsset(request)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Runs one export at a time; a request that arrives while another is in
    /// flight is queued and drained once the current one finishes, since
    /// spawning concurrent Blender export processes isn't safe. The sheet
    /// dismisses as soon as the user confirms (see the "Cook" button above) —
    /// progress from here on shows up in the Tasks panel, same as Gaussian
    /// cook jobs.
    private func exportRuntimeAsset(_ request: RuntimeExportRequest) {
        guard !isExportingRuntimeAsset else {
            runtimeExportWorkQueue.append(request)
            return
        }
        guard let exporterScript = findExportUntoldScript() else {
            showStatus("export-untold script not found", isError: true)
            Logger.log(message: "❌ export-untold script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold")
            return
        }

        isExportingRuntimeAsset = true
        showStatus("Exporting \(request.sourceURL.lastPathComponent)...")
        let task = TaskCenter.begin(
            "Exporting \(request.sourceURL.lastPathComponent)",
            detail: "export-untold → \(request.outputURL.lastPathComponent)"
        )
        let convertOrientation = exportConvertOrientation
        let sourceOrientation = exportSourceOrientation
        let compressGeometry = exportCompressGeometry
        let compressTextures = exportCompressTextures
        let astcencBin = astcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("untold-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("untold-export-\(UUID().uuidString).err")
            task.attach(process: process)

            do {
                try FileManager.default.createDirectory(at: request.destinationFolder, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: request.outputURL.path) {
                    try FileManager.default.removeItem(at: request.outputURL)
                }
                FileManager.default.createFile(atPath: outputLogURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputLogURL)
                let errorHandle = try FileHandle(forWritingTo: errorLogURL)
                defer {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    try? FileManager.default.removeItem(at: outputLogURL)
                    try? FileManager.default.removeItem(at: errorLogURL)
                }

                process.executableURL = exporterScript
                var arguments = [
                    "--input", request.sourceURL.path,
                    "--output", request.outputURL.path,
                ]
                if request.category == .animations {
                    arguments.append("--animation")
                }
                if convertOrientation {
                    arguments.append("--ConvertOrientation")
                    arguments.append(contentsOf: ["--source-orientation", sourceOrientation])
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
                }
                process.arguments = arguments
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                try process.run()
                process.waitUntilExit()

                let stdout = (try? String(contentsOf: outputLogURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errorLogURL, encoding: .utf8)) ?? ""

                DispatchQueue.main.async {
                    if !stdout.isEmpty {
                        Logger.log(message: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if !stderr.isEmpty {
                        Logger.log(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                let wasCancelled = task.isCancelRequested
                let exportSucceeded = process.terminationStatus == 0 && !wasCancelled

                if exportSucceeded, compressTextures {
                    let texturesDir = request.destinationFolder.appendingPathComponent("Textures")
                    if FileManager.default.fileExists(atPath: texturesDir.path),
                       let texbakeScript = findTexbakeScript()
                    {
                        task.setDetail("Baking textures (ASTC)…")
                        DispatchQueue.main.async { showStatus("Baking textures (ASTC)...") }
                        let bakeResult = runTexbakeStep(script: texbakeScript, arguments: ["--dir", texturesDir.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !bakeResult.stdout.isEmpty {
                                Logger.log(message: bakeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !bakeResult.stderr.isEmpty {
                                Logger.log(message: bakeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }

                        task.setDetail("Patching texture references…")
                        DispatchQueue.main.async { showStatus("Patching texture references...") }
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !patchResult.stdout.isEmpty {
                                Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stderr.isEmpty {
                                Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — asset imported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                if wasCancelled {
                    // Don't leave a half-written runtime asset behind.
                    try? FileManager.default.removeItem(at: request.outputURL)
                    task.markCancelled("Cancelled by user")
                } else if exportSucceeded {
                    task.succeed("Wrote \(request.outputURL.lastPathComponent)")
                } else {
                    task.fail("export-untold exited with status \(process.terminationStatus) (see Console)")
                }

                DispatchQueue.main.async {
                    if wasCancelled {
                        Logger.log(message: "Export cancelled for \(request.sourceURL.lastPathComponent)")
                        showStatus("Export cancelled")
                    } else if exportSucceeded {
                        loadAssets()
                        showStatus("Exported \(request.outputURL.lastPathComponent)")
                    } else {
                        showStatus("Export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    }
                    finishRuntimeExport()
                }
            } catch {
                task.fail(error.localizedDescription)
                DispatchQueue.main.async {
                    Logger.log(message: "❌ Export failed: \(error)")
                    showStatus("Export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    finishRuntimeExport()
                }
            }
        }
    }

    /// Marks the current export slot free and, if a request queued up behind
    /// it while it ran, immediately starts that one.
    private func finishRuntimeExport() {
        isExportingRuntimeAsset = false
        if !runtimeExportWorkQueue.isEmpty {
            exportRuntimeAsset(runtimeExportWorkQueue.removeFirst())
        }
    }

    private func queueTilesExport(sourceURL: URL, destinationFolder: URL) {
        let outputDirURL = destinationFolder.appendingPathComponent("tile_exports", isDirectory: true)
        let request = TilesExportRequest(
            sourceURL: sourceURL,
            destinationFolder: destinationFolder,
            outputDirURL: outputDirURL
        )
        tilesExportQueue.append(request)
        presentNextTilesExportIfNeeded()
    }

    private func presentNextTilesExportIfNeeded() {
        guard pendingTilesExport == nil, !tilesExportQueue.isEmpty else { return }
        pendingTilesExport = tilesExportQueue.removeFirst()
    }

    private func tilesExportSheet(for request: TilesExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cook Tiled Stream Model")
                .font(.title2)
                .bold()

            Text("Cook this USD or .blend source into tile payloads and a manifest JSON using export-untold-tiles; the source stays next to the output.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output directory")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.top, 6)
                Text(request.outputDirURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Tile size (world units)")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X").font(.caption)
                        TextField("25", text: $exportTileSizeX)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y").font(.caption)
                        TextField("10000", text: $exportTileSizeY)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Z").font(.caption)
                        TextField("25", text: $exportTileSizeZ)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Toggle("Auto tile size", isOn: $exportAutoTileSize)
                Toggle("Generate HLOD", isOn: $exportGenerateHLOD)
                Toggle("Generate LOD", isOn: $exportGenerateLOD)
                Toggle("Compress geometry (LZ4)", isOn: $exportCompressGeometry)
                    .help("Compresses vertex and index data with LZ4. Requires the Python lz4 package.")
                if exportCompressGeometry {
                    Text("Requires: pip install lz4")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .padding(.leading, 20)
                }

                Toggle("Compress textures (ASTC)", isOn: $exportCompressTextures)
                    .help("Converts textures to GPU-native ASTC format. Requires astcenc and the Python Pillow package.")
                if exportCompressTextures {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Link("Install astcenc →", destination: URL(string: "https://github.com/ARM-software/astc-encoder/releases")!)
                                .font(.caption)
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            Text("Also requires: pip install Pillow")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("astcenc path (optional)")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            HStack {
                                TextField("/opt/homebrew/bin/astcenc", text: $astcencBinPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.title = "Select astcenc binary"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        astcencBinPath = url.path
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }

                Toggle("Quad-tree partitioning", isOn: $exportQuadTree)
                Toggle("Dry run", isOn: $exportDryRun)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingTilesExport = nil
                    presentNextTilesExportIfNeeded()
                }

                Button("Cook") {
                    pendingTilesExport = nil
                    presentNextTilesExportIfNeeded()
                    exportTilesAsset(request)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Same pattern as exportRuntimeAsset: dismiss immediately, queue behind
    /// an in-flight export rather than dropping the request.
    private func exportTilesAsset(_ request: TilesExportRequest) {
        guard !isExportingTilesAsset else {
            tilesExportWorkQueue.append(request)
            return
        }
        guard let exporterScript = findExportUntoldTilesScript() else {
            showStatus("export-untold-tiles script not found", isError: true)
            Logger.log(message: "❌ export-untold-tiles script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold-tiles")
            return
        }

        isExportingTilesAsset = true
        showStatus("Exporting tiles for \(request.sourceURL.lastPathComponent)...")
        let task = TaskCenter.begin(
            "Exporting tiles for \(request.sourceURL.lastPathComponent)",
            detail: "export-untold-tiles → \(request.outputDirURL.lastPathComponent)/"
        )
        let tileSizeX = exportTileSizeX
        let tileSizeY = exportTileSizeY
        let tileSizeZ = exportTileSizeZ
        let compressGeometry = exportCompressGeometry
        let compressTextures = exportCompressTextures
        let astcencBin = astcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let quadTree = exportQuadTree
        let autoTileSize = exportAutoTileSize
        let generateHLOD = exportGenerateHLOD
        let generateLOD = exportGenerateLOD
        let dryRun = exportDryRun

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("untold-tiles-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("untold-tiles-export-\(UUID().uuidString).err")
            task.attach(process: process)

            do {
                try FileManager.default.createDirectory(at: request.destinationFolder, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: outputLogURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputLogURL)
                let errorHandle = try FileHandle(forWritingTo: errorLogURL)
                defer {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    try? FileManager.default.removeItem(at: outputLogURL)
                    try? FileManager.default.removeItem(at: errorLogURL)
                }

                process.executableURL = exporterScript
                var arguments = [
                    "--input", request.sourceURL.path,
                    "--output-dir", request.outputDirURL.path,
                ]
                if let x = Double(tileSizeX), x > 0 {
                    arguments.append(contentsOf: ["--tile-size-x", tileSizeX])
                }
                if let y = Double(tileSizeY), y > 0 {
                    arguments.append(contentsOf: ["--tile-size-y", tileSizeY])
                }
                if let z = Double(tileSizeZ), z > 0 {
                    arguments.append(contentsOf: ["--tile-size-z", tileSizeZ])
                }
                if autoTileSize {
                    arguments.append("--auto-tile-size")
                }
                if generateHLOD {
                    arguments.append("--generate-hlod")
                }
                if generateLOD {
                    arguments.append("--generate-lod")
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
                }
                if quadTree {
                    arguments.append("--quadtree")
                }
                if dryRun {
                    arguments.append("--dry-run")
                }
                process.arguments = arguments
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                try process.run()
                process.waitUntilExit()

                let stdout = (try? String(contentsOf: outputLogURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errorLogURL, encoding: .utf8)) ?? ""

                DispatchQueue.main.async {
                    if !stdout.isEmpty {
                        Logger.log(message: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if !stderr.isEmpty {
                        Logger.log(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                let wasCancelled = task.isCancelRequested
                let exportSucceeded = process.terminationStatus == 0 && !wasCancelled

                if exportSucceeded, compressTextures {
                    let texturesDir = request.outputDirURL.appendingPathComponent("Textures")
                    if FileManager.default.fileExists(atPath: texturesDir.path),
                       let texbakeScript = findTexbakeScript()
                    {
                        task.setDetail("Baking textures (ASTC)…")
                        DispatchQueue.main.async { showStatus("Baking textures (ASTC)...") }
                        let bakeResult = runTexbakeStep(script: texbakeScript, arguments: ["--dir", texturesDir.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !bakeResult.stdout.isEmpty {
                                Logger.log(message: bakeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !bakeResult.stderr.isEmpty {
                                Logger.log(message: bakeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }

                        task.setDetail("Patching texture references…")
                        DispatchQueue.main.async { showStatus("Patching texture references...") }
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputDirURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !patchResult.stdout.isEmpty {
                                Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stderr.isEmpty {
                                Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — tiles imported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                if wasCancelled {
                    task.markCancelled("Cancelled by user")
                } else if exportSucceeded {
                    task.succeed("Wrote tiles to \(request.outputDirURL.lastPathComponent)/")
                } else {
                    task.fail("export-untold-tiles exited with status \(process.terminationStatus) (see Console)")
                }

                DispatchQueue.main.async {
                    if wasCancelled {
                        Logger.log(message: "Tiles export cancelled for \(request.sourceURL.lastPathComponent)")
                        showStatus("Tiles export cancelled")
                    } else if exportSucceeded {
                        loadAssets()
                        showStatus("Exported tiles for \(request.sourceURL.deletingPathExtension().lastPathComponent)")
                    } else {
                        showStatus("Tiles export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    }
                    finishTilesExport()
                }
            } catch {
                task.fail(error.localizedDescription)
                DispatchQueue.main.async {
                    Logger.log(message: "❌ Tiles export failed: \(error)")
                    showStatus("Tiles export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    finishTilesExport()
                }
            }
        }
    }

    /// Same pattern as finishRuntimeExport, for tiled stream-model exports.
    private func finishTilesExport() {
        isExportingTilesAsset = false
        if !tilesExportWorkQueue.isEmpty {
            exportTilesAsset(tilesExportWorkQueue.removeFirst())
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
                            // For HDR, also allow .hdr and .exr files directly in the HDR folder
                            if ["hdr", "exr"].contains(item.pathExtension.lowercased()) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .lut {
                            if item.pathExtension.lowercased() == "cube" {
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
                        } else if category == .models || category == .animations {
                            if runtimeAssetExtensions(for: category).contains(item.pathExtension.lowercased()) || sourceAssetExtensions.contains(item.pathExtension.lowercased()) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .scripts {
                            // Not used anymore due to flat listing, but keep for safety (won’t execute due to continue above)
                        } else if category == .streamModels {
                            if item.pathExtension.lowercased() == "json", isTiledSceneManifest(item) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            } else if item.pathExtension.lowercased() == "remotestream" {
                                categoryAssets.append(Asset(name: item.deletingPathExtension().lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .scenes {
                            // For Scenes, allow files directly in the Scenes folder
                            if item.pathExtension.lowercased() == untoldSceneFileExtension {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
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

    /// Opens the cook sheet for the `.ply` files among `urls`. With none there is nothing
    /// to configure, so the status line says so instead of an empty sheet.
    private func requestGaussianCook(of urls: [URL]) {
        guard let request = GaussianCookRequest(sources: urls) else {
            showStatus("Select .ply files to cook", isError: true)
            return
        }
        pendingGaussianCook = request
    }

    /// Cooks each `.ply` to `.untoldgs` with the sheet's current settings. Every file is
    /// its own job in the Tasks panel (the context-menu cook and an import batch share
    /// this path); the bakes run one after another on the cook queue and the browser
    /// refreshes as each one lands. A failed cook leaves the `.ply` untouched.
    private func cookGaussianSources(_ plyURLs: [URL]) {
        let settings = gaussianCookSettings
        let gaussianRoot = assetBasePath?.appendingPathComponent(AssetCategory.gaussians.rawValue, isDirectory: true)
        showStatus(plyURLs.count == 1
            ? "Cooking \(plyURLs[0].lastPathComponent)..."
            : "Cooking \(plyURLs.count) Gaussian files (see Tasks)...")
        for plyURL in plyURLs {
            let name = plyURL.lastPathComponent
            let outputDirectory = gaussianRoot.flatMap { root -> URL? in
                plyURL.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
                    ? gaussianPackageFolder(for: plyURL, in: root)
                    : nil
            }
            cookGaussianPLYTracked(plyURL: plyURL, settings: settings, outputDirectory: outputDirectory) { result in
                switch result {
                case let .success(bake):
                    loadAssets()
                    let report = bake.cookReport
                    let names = bake.tiers.map(\.url.lastPathComponent).joined(separator: ", ")
                    showStatus("Cooked \(report.keptSplatCount) of \(report.inputSplatCount) splats → \(names)")
                    Logger.log(message: "Cooked \(name): kept \(report.keptSplatCount) of \(report.inputSplatCount) (opacity \(report.prunedByOpacity), degenerate \(report.prunedByDegenerateGeometry), crop \(report.prunedByCrop)), SH degree \(report.shDegree)")
                case let .failure(error):
                    let detail = gaussianCookFailureDetail(error)
                    showStatus("Cook failed for \(name): \(detail)", isError: true)
                    Logger.log(message: "❌ Cook failed for \(name): \(detail). The .ply is unchanged; re-cook from its context menu.")
                }
            }
        }
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

    /// Recursively find all files with a specific extension under a root directory
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

    private func assetRow(_ asset: Asset) -> some View {
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
    private func importPlaceholderRow(_ pending: PendingAssetImport) -> some View {
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

    private func importPlaceholderRows(in folder: URL) -> some View {
        ForEach(placeholderImports(pendingImports, in: folder)) { pending in
            importPlaceholderRow(pending)
        }
    }

    /// Shared row list used by both the flat-category listing and
    /// folderContentsView. Only the folder-tap navigation differs per call site.
    private func assetRowList(_ assets: [Asset], spacing: CGFloat, onFolderTap: @escaping (Asset) -> Void) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(assets) { asset in
                assetRow(asset)
                    // Rows drag into the viewport or the hierarchy; the drop decides
                    // whether the asset can be placed (see AssetPlacement.swift).
                    .draggable(AssetDragPayload(asset: asset))
                    .contextMenu {
                        if asset.category == AssetCategory.gaussians.rawValue,
                           asset.path.pathExtension.lowercased() == "ply"
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
    private func folderContentsView(for folder: URL, selectionManager _: SelectionManager) -> some View {
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
                        let allowedExtensions: Set<String> = Set(["utex", "png", "jpg", "jpeg", "hdr", "exr", "cube", "tif", "tiff", "ply", "untoldgs", "json", "uscript", "remotestream"])
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

    // MARK: - Select Asset

    private func selectAsset(_ asset: Asset) {
        selectedAsset = asset
        selectedAssetName = asset.name
        updateTargetEntityName(for: selectionManager.selectedEntity)
    }

    private func selectedSceneAuthoredAsset() -> Asset? {
        guard let selectedAsset else {
            return nil
        }

        if let runtimeAsset = resolvedRuntimeAsset(for: selectedAsset),
           runtimeAsset.category == AssetCategory.models.rawValue,
           runtimeModelAssetExtensions.contains(runtimeAsset.path.pathExtension.lowercased())
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

    private func loadSelectedSceneAuthoredPayload() {
        guard let asset = selectedSceneAuthoredAsset() else {
            showStatus("Select a .untold model or tiled scene manifest first", isError: true)
            return
        }

        editor_loadSceneAuthoredFromAsset(asset)
        showStatus("Loading authored cameras/lights: \(asset.name)...")
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

    private func selectedMaterialTarget() -> (entityId: EntityID, meshIndex: Int)? {
        if let inspectedMesh = selectionManager.inspectedMesh,
           inspectedMesh.entityId != .invalid,
           hasComponent(entityId: inspectedMesh.entityId, componentType: RenderComponent.self)
        {
            return (inspectedMesh.entityId, inspectedMesh.meshIndex)
        }

        guard let entityId = selectionManager.selectedEntity,
              entityId != .invalid,
              hasComponent(entityId: entityId, componentType: RenderComponent.self)
        else {
            return nil
        }

        return (entityId, 0)
    }

    private func assignMaterialFolder(_ asset: Asset) {
        guard asset.category == AssetCategory.materials.rawValue, asset.isFolder else {
            return
        }

        guard let target = selectedMaterialTarget() else {
            showStatus("Select a mesh before assigning materials", isError: true)
            return
        }

        let assignments = editorMaterialTextureAssignments(in: asset.path)
        guard assignments.isEmpty == false else {
            showStatus("No recognized material textures in \(asset.name)", isError: true)
            return
        }

        for textureType in TextureType.allCases {
            guard let textureURL = assignments[textureType] else { continue }
            updateMaterialTexture(
                entityId: target.entityId,
                textureType: textureType,
                path: textureURL,
                meshIndex: target.meshIndex
            )
        }

        selectionManager.objectWillChange.send()
        showStatus("Assigned \(assignments.count) material textures from \(asset.name)")
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

    private func loadStreamModel(from asset: Asset) {
        guard let manifestAsset = resolvedTiledSceneManifest(for: asset) else {
            if asset.isFolder {
                showStatus("No tiled scene manifest found in \(asset.name)", isError: true)
            } else {
                showStatus("Selected JSON is not a tiled scene manifest", isError: true)
            }
            return
        }

        let sceneRoot = createEntity()
        let sceneName = manifestAsset.path.deletingPathExtension().lastPathComponent
        setEntityName(entityId: sceneRoot, name: sceneName)

        clearSceneBatches()
        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: sceneRoot, url: manifestAsset.path) { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Stream model loaded: \(sceneName)")
                    showStatus("Loaded stream model: \(sceneName)")
                } else {
                    print("⚠️ Failed to load stream model: \(sceneName)")
                    showStatus("Failed to load stream model: \(sceneName)", isError: true)
                }
                sceneGraphModel.refreshHierarchy()
            }
        }

        selectionManager.selectedEntity = sceneRoot
        showStatus("Loading stream model: \(sceneName)...")
    }

    private func saveRemoteStream(loadImmediately: Bool) {
        guard let basePath = assetBasePath else {
            showStatus("No project loaded", isError: true)
            return
        }

        let urlStr = remoteStreamURLString.trimmingCharacters(in: .whitespaces)

        guard let remoteURL = URL(string: urlStr),
              remoteURL.scheme?.lowercased() == "https",
              let host = remoteURL.host, !host.isEmpty,
              remoteURL.pathExtension.lowercased() == "json"
        else {
            showStatus("URL must be a valid https:// link ending in .json", isError: true)
            return
        }

        let baseName = remoteURL.deletingPathExtension().lastPathComponent
        // Hash the full URL to avoid collisions between manifests with the same filename on different hosts.
        let urlHash = String(format: "%08x", urlStr.utf8.reduce(UInt32(5381)) { ($0 &* 31) &+ UInt32($1) })
        let name = "\(baseName)-\(urlHash)"

        saveRemoteStreamAsset(
            name: name,
            displayName: baseName,
            urlString: urlStr,
            basePath: basePath,
            loadImmediately: loadImmediately
        )
        remoteStreamURLString = ""
    }

    private func saveRemoteStreamAsset(
        name: String,
        displayName: String,
        urlString: String,
        basePath: URL,
        loadImmediately: Bool
    ) {
        let streamModelsFolder = basePath.appendingPathComponent("StreamModels", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: streamModelsFolder, withIntermediateDirectories: true)
            let fileURL = streamModelsFolder
                .appendingPathComponent(name)
                .appendingPathExtension("remotestream")
            try urlString.write(to: fileURL, atomically: true, encoding: .utf8)
            loadAssets()
            let asset = Asset(
                name: displayName,
                category: AssetCategory.streamModels.rawValue,
                path: fileURL,
                isFolder: false
            )
            navigation.lightsSelected = false
            navigation.primitivesSelected = false
            selectedCategory = AssetCategory.streamModels.rawValue
            folderPathStack = []
            if loadImmediately {
                loadRemoteStreamModel(from: asset)
            } else {
                showStatus("Remote stream '\(displayName)' added")
            }
        } catch {
            showStatus("Failed to save remote stream: \(error.localizedDescription)", isError: true)
        }
    }

    private func loadRemoteStreamModel(from asset: Asset) {
        guard let urlStr = try? String(contentsOf: asset.path, encoding: .utf8),
              let url = URL(string: urlStr.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            showStatus("Invalid URL in \(asset.name)", isError: true)
            return
        }

        let sceneRoot = createEntity()
        let sceneName = asset.name
        setEntityName(entityId: sceneRoot, name: sceneName)

        clearSceneBatches()
        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: sceneRoot, url: url) { success in
            DispatchQueue.main.async {
                if success {
                    showStatus("Loaded remote stream: \(sceneName)")
                } else {
                    showStatus("Failed to load remote stream: \(sceneName)", isError: true)
                }
                sceneGraphModel.refreshHierarchy()
            }
        }

        selectionManager.selectedEntity = sceneRoot
        showStatus("Loading remote stream: \(sceneName)...")
    }

    private func handle_add_model_double_click(asset: Asset) {
        if asset.category == AssetCategory.materials.rawValue, asset.isFolder {
            assignMaterialFolder(asset)
            return
        }

        if asset.category == AssetCategory.streamModels.rawValue {
            if asset.path.pathExtension.lowercased() == "remotestream" {
                loadRemoteStreamModel(from: asset)
            } else {
                loadStreamModel(from: asset)
            }
            return
        }

        // Models (.untold, .untoldpack, or a folder's primary) and Gaussian splats (.ply,
        // baked .untoldgs, or an imported package folder) take the same path as a
        // drag-and-drop onto the scene.
        if let placeable = placeableAsset(for: asset) {
            let placement = placeAsset(placeable, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
            return
        }
        if asset.isFolder, asset.category == AssetCategory.gaussians.rawValue {
            showStatus(unsupportedAssetDropMessage(for: asset), isError: true)
            return
        }

        guard let asset = resolvedRuntimeAsset(for: asset) else {
            if asset.isFolder,
               asset.category == AssetCategory.models.rawValue || asset.category == AssetCategory.animations.rawValue
            {
                showStatus("No primary runtime asset found in \(asset.name)", isError: true)
            }
            return
        }

        let filename = asset.path.deletingPathExtension().lastPathComponent
        let runtimeFilename = runtimeAssetFilenameForLoading(asset.path)
        let withExtension = asset.path.pathExtension

        // Handle Animation files (.untold runtime assets in Animations category)
        if asset.category == AssetCategory.animations.rawValue,
           runtimeAnimationAssetExtensions.contains(withExtension.lowercased())
        {
            // Animations require a selected entity to work with
            guard let entityId = selectionManager.selectedEntity,
                  entityId != .invalid
            else {
                print("⚠️ Please select an entity first to add animation")
                showStatus("Select an entity before adding animation", isError: true)
                return
            }

            guard canAuthorAnimationComponent(entityId: entityId) else {
                print("⚠️ Select a mesh node to add animation")
                showStatus("Select a mesh node before adding animation", isError: true)
                return
            }

            // Add the animation to the entity
            setEntityAnimations(entityId: entityId, filename: runtimeFilename, withExtension: withExtension, name: filename)

            // Store the animation file URL in the component
            for targetEntityId in editorAnimationBindingTargetEntities(for: entityId) {
                guard let animationComponent = scene.get(component: AnimationComponent.self, for: targetEntityId) else {
                    continue
                }

                if animationComponent.animationsFilenames.contains(asset.path) == false {
                    animationComponent.animationsFilenames.append(asset.path)
                }
            }

            // Refresh view
            selectionManager.objectWillChange.send()
            showStatus("Queued animation link to \(targetEntityName) (see Console)")
        }
        // Handle Script files (uscript)
        else if asset.category == AssetCategory.scripts.rawValue,
                withExtension.lowercased() == "uscript"
        {
            guard EditorAuthoringMode.sceneCompositionOnly == false else {
                showStatus("Scripts are linked in code for scene-composition projects", isError: true)
                return
            }

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
        // Handle Scene files (.untoldscene)
        else if asset.category == AssetCategory.scenes.rawValue,
                withExtension.lowercased() == untoldSceneFileExtension
        {
            // Show confirmation dialog before loading scene
            pendingSceneToLoad = asset.path
            showSceneLoadConfirmation = true
            editorController?.currentSceneURL = asset.path
        }
        // Handle HDR files (hdr, exr)
        else if asset.category == AssetCategory.hdr.rawValue,
                ["hdr", "exr"].contains(withExtension.lowercased())
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
        EditorGaussianAssetState.shared.clear()

        // Load new scene
        deserializeScene(sceneData: sceneData, onGaussianEntityRestored: restoreEditorGaussianState)

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
