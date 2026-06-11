//
//  QuickPreviewComponent.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation
import UniformTypeIdentifiers
import UntoldEngine

enum QuickPreviewImportMode: String, CaseIterable {
    case untoldAsset
    case tiledScene
    case gaussian

    var menuTitle: String {
        switch self {
        case .untoldAsset:
            return "Load Untold Asset (.untold, USD)"
        case .tiledScene:
            return "Load Tiled Stream (.json)"
        case .gaussian:
            return "Load Gaussian (.ply)"
        }
    }

    var systemImageName: String {
        switch self {
        case .untoldAsset:
            return "cube.fill"
        case .tiledScene:
            return "square.stack.3d.up.fill"
        case .gaussian:
            return "sparkles"
        }
    }

    var filePickerTitle: String {
        switch self {
        case .untoldAsset:
            return "Load Preview - Select Untold or USD Asset"
        case .tiledScene:
            return "Load Preview - Select Tiled Stream Manifest"
        case .gaussian:
            return "Load Preview - Select Gaussian"
        }
    }

    var filePickerMessage: String {
        switch self {
        case .untoldAsset:
            return "Select an Untold runtime asset or USD source asset to preview without creating a project"
        case .tiledScene:
            return "Select a tiled stream manifest to preview without creating a project"
        case .gaussian:
            return "Select a Gaussian PLY file to preview without creating a project"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .untoldAsset:
            return ["untold", "usd", "usda", "usdc", "usdz"].compactMap { UTType(filenameExtension: $0) }
        case .tiledScene:
            return [.json]
        case .gaussian:
            return [UTType(filenameExtension: "ply") ?? .data]
        }
    }
}

/// Marks an entity as being loaded via Quick Preview with an absolute path.
/// These entities cannot be serialized and must be removed before saving the scene.
public class QuickPreviewComponent: Component {
    /// The absolute file path to the original asset
    public var absoluteFilePath: String

    /// The file extension (untold, ply, json, etc.)
    public var fileExtension: String

    /// The original filename without extension
    public var originalFileName: String

    /// Disposable temp cache directory used by converted quick-preview assets.
    public var runtimePreviewDirectoryPath: String

    public required init() {
        absoluteFilePath = ""
        fileExtension = ""
        originalFileName = ""
        runtimePreviewDirectoryPath = ""
    }

    public init(absoluteFilePath: String, fileExtension: String, originalFileName: String) {
        self.absoluteFilePath = absoluteFilePath
        self.fileExtension = fileExtension
        self.originalFileName = originalFileName
        runtimePreviewDirectoryPath = ""
    }
}

struct QuickPreviewRuntimeExportRequest: Identifiable {
    let id = UUID()
    let sourceURL: URL
    let outputURL: URL
}

enum QuickPreviewRuntimeExportCache {
    static let directoryName = "UntoldEditorQuickPreviewExports"
    static let defaultStaleAge: TimeInterval = 24 * 60 * 60

    static func rootDirectory(baseDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        baseDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func cacheDirectory(
        for sourceURL: URL,
        exportID: UUID = UUID(),
        rootDirectory: URL = rootDirectory()
    ) -> URL {
        let baseName = sanitizedFileName(sourceURL.deletingPathExtension().lastPathComponent)
        return rootDirectory.appendingPathComponent("\(baseName)-\(exportID.uuidString)", isDirectory: true)
    }

    static func outputURL(for sourceURL: URL, in cacheDirectory: URL) -> URL {
        cacheDirectory
            .appendingPathComponent(sanitizedFileName(sourceURL.deletingPathExtension().lastPathComponent))
            .appendingPathExtension("untold")
    }

    static func pruneStaleCaches(
        in rootDirectory: URL = rootDirectory(),
        preserving preservedDirectories: Set<URL> = [],
        olderThan staleAge: TimeInterval = defaultStaleAge,
        now: Date = Date(),
        fileManager: FileManager = .default
    ) {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let preservedPaths = Set(preservedDirectories.map(\.standardizedFileURL.path))
        for url in contents where preservedPaths.contains(url.standardizedFileURL.path) == false {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  let modifiedAt = values.contentModificationDate
            else {
                continue
            }

            if now.timeIntervalSince(modifiedAt) > staleAge {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    static func removeCacheDirectory(at url: URL, fileManager: FileManager = .default) {
        let rootPath = rootDirectory().standardizedFileURL.path
        let targetURL = url.standardizedFileURL
        guard targetURL.path.hasPrefix(rootPath) else {
            return
        }

        try? fileManager.removeItem(at: targetURL)
    }

    private static func sanitizedFileName(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return sanitized.isEmpty ? "QuickPreview" : sanitized
    }
}
