//
//  AssetModel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

public struct Asset: Identifiable {
    public let id = UUID()
    public let name: String
    public let category: String
    public let path: URL
    var isFolder: Bool = false
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
