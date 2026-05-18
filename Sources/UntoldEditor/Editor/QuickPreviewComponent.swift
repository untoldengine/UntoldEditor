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
            return "Load Untold Asset (.untold)"
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
            return "Load Preview - Select Untold Asset"
        case .tiledScene:
            return "Load Preview - Select Tiled Stream Manifest"
        case .gaussian:
            return "Load Preview - Select Gaussian"
        }
    }

    var filePickerMessage: String {
        switch self {
        case .untoldAsset:
            return "Select an Untold runtime asset to preview without creating a project"
        case .tiledScene:
            return "Select a tiled stream manifest to preview without creating a project"
        case .gaussian:
            return "Select a Gaussian PLY file to preview without creating a project"
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .untoldAsset:
            return [UTType(filenameExtension: "untold") ?? .data]
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

    public required init() {
        absoluteFilePath = ""
        fileExtension = ""
        originalFileName = ""
    }

    public init(absoluteFilePath: String, fileExtension: String, originalFileName: String) {
        self.absoluteFilePath = absoluteFilePath
        self.fileExtension = fileExtension
        self.originalFileName = originalFileName
    }
}
