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
    /// Whether the "GameData" sidebar group (the fixed categories + any custom
    /// root folders, all of which physically live inside GameData) is expanded.
    /// Separate from `rootExpanded`, which gates the whole tree under the
    /// project name -- this only controls GameData's own children, so
    /// `Resources` stays visible (and independently expandable) regardless.
    @Published var gameDataExpanded: Bool = true
    /// True when the Lights shelf (a fixed pseudo-category, not backed by disk) is
    /// selected. Overrides the category and generic-directory selection.
    @Published var lightsSelected: Bool = false
    /// Same as `lightsSelected`, for the Primitives shelf (Cube/Sphere/Plane).
    @Published var primitivesSelected: Bool = false
    /// Same again, for the Entities shelf: kinds of entity added by loaded code that are
    /// neither primitives nor lights.
    @Published var entitiesSelected: Bool = false
    /// Non-nil while a sidebar folder row is showing its inline rename field (see
    /// `directoryNode`'s "Rename" context menu item). Never a fixed root (a category,
    /// or Resources itself) -- only a folder the user created can be renamed.
    @Published var renamingDirectoryURL: URL?
}
