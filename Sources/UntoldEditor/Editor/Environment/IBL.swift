//
//  IBL.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

func addIBL(asset: Asset?) {
    let selectedCategory: AssetCategory = .hdr

    if let asset, selectedCategory.rawValue == asset.category {
        let filename = asset.path.lastPathComponent
        let directoryURL = asset.path.deletingLastPathComponent()

        // Verify HDR file exists before attempting to load
        let hdrPath = directoryURL.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: hdrPath.path) else {
            Logger.log(message: "⚠️ HDR file not found: \(hdrPath.path)")
            return
        }

        generateHDR(filename, from: directoryURL)

        // Only enable IBL if HDR was successfully loaded
        if iblSuccessful {
            applyIBL = true
            EditorSceneDirtyState.shared.markDirty()
            Logger.log(message: "✅ IBL enabled with HDR: \(filename)")
        } else {
            Logger.log(message: "⚠️ Failed to enable IBL - HDR loading failed")
        }
    }
}
