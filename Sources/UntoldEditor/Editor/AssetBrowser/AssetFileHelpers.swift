//
//  AssetFileHelpers.swift
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

let runtimeAssetExtension = "untold"
let runtimeModelAssetExtensions: Set<String> = [runtimeAssetExtension, "untoldpack"]
let runtimeAnimationAssetExtensions: Set<String> = [runtimeAssetExtension, "untoldanim"]
let allRuntimeAssetExtensions = runtimeModelAssetExtensions.union(runtimeAnimationAssetExtensions)
private let runtimeTextureFolderNames = ["Textures", "textures"]
let sourceAssetExtensions: Set<String> = ["usd", "usda", "usdc", "usdz", "blend"]
private let streamModelResourceFolderNames = ["tile_exports", "tile_export", "Textures", "textures"]
private let materialTextureExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff"]

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
