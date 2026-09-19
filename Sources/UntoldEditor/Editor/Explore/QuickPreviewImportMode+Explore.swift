//
//  QuickPreviewImportMode+Explore.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

extension QuickPreviewImportMode {
    var exploreTitle: String {
        switch self {
        case .untoldAsset:
            return "Untold Asset"
        case .tiledScene:
            return "Tiled Scene"
        case .gaussian:
            return "Gaussian Splat"
        }
    }

    var exploreSubtitle: String {
        switch self {
        case .untoldAsset:
            return "Open a runtime asset exported from Blender or converted from USD."
        case .tiledScene:
            return "Open a tiled stream manifest for larger scenes."
        case .gaussian:
            return "Open a Gaussian splat point-cloud scene."
        }
    }

    var exploreFileTypes: String {
        switch self {
        case .untoldAsset:
            return ".untold, USD"
        case .tiledScene:
            return ".json"
        case .gaussian:
            return ".ply, .untoldgs"
        }
    }

    var exploreLoadedSubtitle: String {
        switch self {
        case .untoldAsset:
            return "Untold Asset Preview"
        case .tiledScene:
            return "Tiled Scene Preview"
        case .gaussian:
            return "Gaussian Splat Preview"
        }
    }
}
