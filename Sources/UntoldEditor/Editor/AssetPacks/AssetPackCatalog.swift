//
//  AssetPackCatalog.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import Foundation
import SwiftUI
import UntoldEngine

struct AssetPackCatalog: Decodable, Equatable {
    var version: String
    var assets: [AssetPackCatalogItem]
}

struct AssetPackCatalogItem: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let version: String
    let downloadURL: String
    let size: String
    let thumbnailName: String?
    let replacePaths: [String]

    init(
        id: String,
        name: String,
        description: String,
        version: String,
        downloadURL: String,
        size: String,
        thumbnailName: String? = nil,
        replacePaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.downloadURL = downloadURL
        self.size = size
        self.thumbnailName = thumbnailName
        self.replacePaths = replacePaths
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case version
        case downloadURL
        case size
        case thumbnailName
        case replacePaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        version = try container.decode(String.self, forKey: .version)
        downloadURL = try container.decode(String.self, forKey: .downloadURL)
        size = try container.decode(String.self, forKey: .size)
        thumbnailName = try container.decodeIfPresent(String.self, forKey: .thumbnailName)
        replacePaths = try container.decodeIfPresent([String].self, forKey: .replacePaths) ?? []
    }

    var category: String {
        if id.contains("archviz") || name.localizedCaseInsensitiveContains("arch") {
            return "Architecture"
        }
        if id.contains("stream") || name.localizedCaseInsensitiveContains("stream") {
            return "Streaming"
        }
        if id.contains("digital") || name.localizedCaseInsensitiveContains("digital") {
            return "Digital Twin"
        }
        return "Starter"
    }

    var tags: [String] {
        var values = ["free"]
        if category != "Starter" {
            values.append(category.lowercased())
        }
        return values
    }
}

private let assetPackKnownGameDataFolders = [
    "Models", "Animations", "Gaussians", "Scripts",
    "StreamModels", "Textures", "Shaders", "Scenes", "LUT",
]

enum AssetPackInstallSource: Equatable {
    case cache
    case download
}

struct AssetPackInstallResult: Equatable {
    let fileCount: Int
    let source: AssetPackInstallSource
}

func defaultAssetPackCatalog() -> AssetPackCatalog {
    AssetPackCatalog(
        version: "1.0.0",
        assets: [
            AssetPackCatalogItem(
                id: "starter",
                name: "StarterPack",
                description: "Soccer field, goals, ball, and a sample scene.",
                version: "1.0.0",
                downloadURL: "https://d8pyi1c08k1w.cloudfront.net/StarterPack.zip",
                size: "5.3 MB",
                thumbnailName: "starterpack",
                replacePaths: ["Models/starterpack"]
            ),
        ]
    )
}

func configuredAssetPackCatalogURL(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    userDefaults: UserDefaults = .standard
) -> URL? {
    let configuredValue = environment["UNTOLD_ASSET_CATALOG_URL"]
        ?? userDefaults.string(forKey: "UntoldAssetCatalogURL")
    guard let configuredValue,
          configuredValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    else {
        return nil
    }

    return URL(string: configuredValue.trimmingCharacters(in: .whitespacesAndNewlines))
}

func decodeAssetPackCatalog(from data: Data) throws -> AssetPackCatalog {
    try JSONDecoder().decode(AssetPackCatalog.self, from: data)
}

func fetchAssetPackCatalog(from catalogURL: URL) async throws -> AssetPackCatalog {
    let (data, response) = try await URLSession.shared.data(from: catalogURL)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw AssetPackInstallError.downloadFailed("Failed to fetch asset catalog.")
    }
    return try decodeAssetPackCatalog(from: data)
}

func assetPackCategoryName(for item: AssetPackCatalogItem) -> String {
    item.category
}

func assetPackCategoryNames(for items: [AssetPackCatalogItem]) -> [String] {
    Array(Set(items.map(assetPackCategoryName(for:)))).sorted {
        $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
    }
}

func filteredAssetPackItems(
    _ items: [AssetPackCatalogItem],
    selectedCategory: String?,
    searchQuery: String
) -> [AssetPackCatalogItem] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

    return items.filter { item in
        if let selectedCategory, assetPackCategoryName(for: item) != selectedCategory {
            return false
        }

        guard query.isEmpty == false else { return true }

        return item.name.localizedCaseInsensitiveContains(query)
            || item.description.localizedCaseInsensitiveContains(query)
            || item.id.localizedCaseInsensitiveContains(query)
            || assetPackCategoryName(for: item).localizedCaseInsensitiveContains(query)
            || item.tags.contains { $0.localizedCaseInsensitiveContains(query) }
    }
}

enum AssetPackInstallError: Error, LocalizedError {
    case missingProject
    case invalidURL(String)
    case downloadFailed(String)
    case archiveListingFailed(String)
    case unsafeArchiveEntry(String)
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingProject:
            return "No project is loaded."
        case let .invalidURL(url):
            return "Invalid download URL: \(url)"
        case let .downloadFailed(message):
            return "Download failed: \(message)"
        case let .archiveListingFailed(message):
            return "Unable to inspect asset package: \(message)"
        case let .unsafeArchiveEntry(entry):
            return "Asset package contains an unsafe path: \(entry)"
        case let .extractionFailed(message):
            return "Extraction failed: \(message)"
        }
    }
}

func installAssetPack(
    _ item: AssetPackCatalogItem,
    into gameDataURL: URL?,
    cacheRoot: URL = userAssetPackCacheRoot(),
    fileManager fm: FileManager = .default,
    task: EditorTaskHandle? = nil
) async throws -> AssetPackInstallResult {
    guard let gameDataURL else {
        throw AssetPackInstallError.missingProject
    }

    task?.setDetail("Checking local cache...")
    if let fileCount = try installCachedAssetPack(item, into: gameDataURL, cacheRoot: cacheRoot, fileManager: fm) {
        Logger.log(message: "Asset pack found in cache: \(item.name)")
        return AssetPackInstallResult(fileCount: fileCount, source: .cache)
    }

    task?.setDetail("Downloading package...")
    let zipURL = try await downloadAssetPack(item)
    defer { try? fm.removeItem(at: zipURL) }

    task?.setDetail("Extracting package...")
    let extractDir = try extractAssetPackArchive(zipURL, fileManager: fm)
    defer { try? fm.removeItem(at: extractDir) }

    let packRoot = findAssetPackRoot(in: extractDir, fileManager: fm)
    task?.setDetail("Saving package to local cache...")
    let cachedPackRoot = try cacheAssetPack(packRoot, item: item, cacheRoot: cacheRoot, fileManager: fm)
    task?.setDetail("Installing into GameData...")
    try removeAssetPackReplacePaths(for: item, in: gameDataURL, fileManager: fm)
    let fileCount = try mergeAssetPack(from: cachedPackRoot, into: gameDataURL, fileManager: fm)
    Logger.log(message: "Downloaded asset pack and saved to cache: \(item.name)")
    return AssetPackInstallResult(fileCount: fileCount, source: .download)
}

func downloadAssetPack(_ item: AssetPackCatalogItem) async throws -> URL {
    guard let url = URL(string: item.downloadURL) else {
        throw AssetPackInstallError.invalidURL(item.downloadURL)
    }

    Logger.log(message: "Downloading asset pack: \(item.name)")
    let (tempURL, response) = try await URLSession.shared.download(from: url)

    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
        throw AssetPackInstallError.downloadFailed("Server returned a non-200 response.")
    }

    let zipURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("zip")
    try FileManager.default.moveItem(at: tempURL, to: zipURL)
    return zipURL
}

func validateAssetPackArchiveEntries(_ archiveURL: URL) throws {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
    process.arguments = ["-1", archiveURL.path]
    process.standardOutput = outputPipe
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    guard process.terminationStatus == 0 else {
        throw AssetPackInstallError.archiveListingFailed(error.isEmpty ? output : error)
    }

    for entry in output.split(separator: "\n").map(String.init) {
        let normalizedEntry = entry.replacingOccurrences(of: "\\", with: "/")
        let components = normalizedEntry.split(separator: "/", omittingEmptySubsequences: false)
        if normalizedEntry.hasPrefix("/") || components.contains("..") {
            throw AssetPackInstallError.unsafeArchiveEntry(entry)
        }
    }
}

func extractAssetPackArchive(
    _ archiveURL: URL,
    fileManager fm: FileManager = .default
) throws -> URL {
    try validateAssetPackArchiveEntries(archiveURL)

    let extractDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

    let errorPipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = ["-q", archiveURL.path, "-d", extractDir.path]
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
        throw AssetPackInstallError.extractionFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    return extractDir
}

func findAssetPackRoot(in extractDir: URL, fileManager fm: FileManager = .default) -> URL {
    guard let contents = try? fm.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
        return extractDir
    }

    let directories = contents.filter { url in
        var isDir: ObjCBool = false
        fm.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue && url.lastPathComponent.hasPrefix("__") == false
    }

    return directories.count == 1 ? directories[0] : extractDir
}

func userAssetPackCacheRoot(fileManager fm: FileManager = .default) -> URL {
    if let applicationSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
        return applicationSupport
            .appendingPathComponent("UntoldEditor", isDirectory: true)
            .appendingPathComponent("AssetPacks", isDirectory: true)
    }

    return fm.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
        .appendingPathComponent("UntoldEditor", isDirectory: true)
        .appendingPathComponent("AssetPacks", isDirectory: true)
}

func assetPackCacheKey(for item: AssetPackCatalogItem) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    func sanitized(_ value: String) -> String {
        value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.reduce(into: "") { $0.append($1) }
    }

    return [item.id, item.version].map(sanitized).joined(separator: "-")
}

func cachedAssetPackRoot(for item: AssetPackCatalogItem, cacheRoot: URL) -> URL {
    cacheRoot.appendingPathComponent(assetPackCacheKey(for: item), isDirectory: true)
}

func installCachedAssetPack(
    _ item: AssetPackCatalogItem,
    into gameDataURL: URL,
    cacheRoot: URL,
    fileManager fm: FileManager = .default
) throws -> Int? {
    let cachedPackRoot = cachedAssetPackRoot(for: item, cacheRoot: cacheRoot)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: cachedPackRoot.path, isDirectory: &isDir), isDir.boolValue else {
        return nil
    }

    try removeAssetPackReplacePaths(for: item, in: gameDataURL, fileManager: fm)
    return try mergeAssetPack(from: cachedPackRoot, into: gameDataURL, fileManager: fm)
}

func cacheAssetPack(
    _ packRoot: URL,
    item: AssetPackCatalogItem,
    cacheRoot: URL,
    fileManager fm: FileManager = .default
) throws -> URL {
    let cachedPackRoot = cachedAssetPackRoot(for: item, cacheRoot: cacheRoot)
    let stagingRoot = cacheRoot
        .appendingPathComponent(".staging", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try fm.createDirectory(at: stagingRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: stagingRoot) }

    try fm.copyItem(at: packRoot, to: stagingRoot)
    if fm.fileExists(atPath: cachedPackRoot.path) {
        try fm.removeItem(at: cachedPackRoot)
    }
    try fm.createDirectory(at: cachedPackRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fm.moveItem(at: stagingRoot, to: cachedPackRoot)

    return cachedPackRoot
}

func mergeAssetPack(
    from packRoot: URL,
    into gameDataURL: URL,
    fileManager fm: FileManager = .default
) throws -> Int {
    var totalFiles = 0
    for folderName in assetPackKnownGameDataFolders {
        let source = packRoot.appendingPathComponent(folderName, isDirectory: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else {
            continue
        }

        let destination = gameDataURL.appendingPathComponent(folderName, isDirectory: true)
        totalFiles += try mergeAssetPackDirectory(from: source, into: destination, fileManager: fm)
    }
    return totalFiles
}

func removeAssetPackReplacePaths(
    for item: AssetPackCatalogItem,
    in gameDataURL: URL,
    fileManager fm: FileManager = .default
) throws {
    for replacePath in item.replacePaths {
        let safePath = try validatedAssetPackReplacePath(replacePath)
        let destination = gameDataURL.appendingPathComponent(safePath, isDirectory: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
    }
}

private func validatedAssetPackReplacePath(_ path: String) throws -> String {
    let normalizedPath = path.replacingOccurrences(of: "\\", with: "/")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let components = normalizedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard normalizedPath.isEmpty == false,
          normalizedPath.hasPrefix("/") == false,
          components.contains("..") == false,
          assetPackKnownGameDataFolders.contains(components.first ?? "")
    else {
        throw AssetPackInstallError.unsafeArchiveEntry(path)
    }

    return normalizedPath
}

private func mergeAssetPackDirectory(
    from source: URL,
    into destination: URL,
    fileManager fm: FileManager
) throws -> Int {
    if fm.fileExists(atPath: destination.path) == false {
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey])
    var fileCount = 0

    for item in contents {
        var isDir: ObjCBool = false
        fm.fileExists(atPath: item.path, isDirectory: &isDir)

        let destinationItem = destination.appendingPathComponent(item.lastPathComponent, isDirectory: isDir.boolValue)
        if isDir.boolValue {
            fileCount += try mergeAssetPackDirectory(from: item, into: destinationItem, fileManager: fm)
        } else {
            if fm.fileExists(atPath: destinationItem.path) {
                try fm.removeItem(at: destinationItem)
            }
            try fm.copyItem(at: item, to: destinationItem)
            fileCount += 1
        }
    }

    return fileCount
}
