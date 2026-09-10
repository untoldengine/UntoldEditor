//
//  AssetBrowserNavigationState.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where the user is in the Content (asset) browser: the selected category or
/// folder, the open subfolder trail, the expanded tree nodes and the highlighted
/// asset. Owned by the editor view rather than the browser itself so switching
/// the bottom dock to another tab and back restores the same place.
final class AssetBrowserNavigationState: ObservableObject {
    @Published var selectedCategory: String? = AssetCategory.models.rawValue
    @Published var selectedAssetName: String?
    @Published var folderPathStack: [URL] = []
    @Published var expandedDirs: Set<URL> = []
    /// Non-nil when a folder outside the fixed categories (e.g. a root-level
    /// directory the user created) is selected. Overrides the category selection.
    @Published var selectedDirURL: URL?
    @Published var rootExpanded: Bool = true
    /// True when the Lights shelf (a fixed pseudo-category, not backed by disk) is
    /// selected. Overrides the category and generic-directory selection.
    @Published var lightsSelected: Bool = false
    /// Same as `lightsSelected`, for the Primitives shelf (Cube/Sphere/Plane).
    @Published var primitivesSelected: Bool = false
}
