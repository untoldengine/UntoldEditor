//
//  AssetBrowserView+DirectoryTree.swift
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

extension AssetBrowserView {
    // MARK: - Finder helpers

    func categoryRootURL(_ category: AssetCategory) -> URL? {
        assetBasePath?.appendingPathComponent(category.rawValue, isDirectory: true)
    }

    /// The project's `Resources/` folder, browsable as a second root alongside
    /// `GameData`'s categories -- where import now puts artist sources (see
    /// `AssetBrowserView+Import.swift`). Nil on the legacy layout, which has no
    /// `Resources/` folder.
    var resourcesRootURL: URL? {
        assetBasePath.flatMap { ProjectLayout.detect(gameDataDirectory: $0).resourcesDirectory }
    }

    /// Root-level folders the user created that aren't one of the fixed categories.
    var customRootFolders: [URL] {
        guard let root = assetBasePath else { return [] }
        let categoryNames = Set(AssetCategory.allCases.map(\.rawValue))
        return subdirectories(of: root).filter { !categoryNames.contains($0.lastPathComponent) }
    }

    /// The directory currently shown on the right: a generic (non-category)
    /// selection wins, otherwise the open subfolder, otherwise the selected
    /// category's root folder.
    var currentDirectoryURL: URL? {
        if let generic = selectedDirURL {
            return generic
        }
        if let folder = currentFolderPath {
            return folder
        }
        guard let raw = selectedCategory, let category = AssetCategory(rawValue: raw) else { return nil }
        return categoryRootURL(category)
    }

    /// Category owning `url` (matched by the top-level folder under `GameData`), used
    /// to pick import file types for generic folders. `Resources/` has no categories of
    /// its own -- a source there is category-agnostic until the user cooks it as
    /// something specific (see the context menu in `AssetBrowserView+Contents.swift`),
    /// so this only ever matches a `GameData`-side path.
    func inferCategory(for url: URL?) -> AssetCategory? {
        guard let url, let root = assetBasePath?.standardizedFileURL else { return nil }
        let rootComponents = root.pathComponents
        let comps = url.standardizedFileURL.pathComponents
        guard comps.count > rootComponents.count, comps.starts(with: rootComponents) else { return nil }
        return AssetCategory(rawValue: comps[rootComponents.count])
    }

    /// One step of the breadcrumb shown above the folder contents: a display name, the
    /// URL tapping it navigates to, and (for a GameData-side segment) the category that
    /// navigation needs -- nil for a Resources/custom-root segment, which navigates via
    /// the generic `selectedDirURL` path instead (see `selectBreadcrumb`).
    struct BreadcrumbSegment: Identifiable {
        let name: String
        let url: URL
        let category: String?
        var id: String { url.standardizedFileURL.path }
    }

    /// Segments for the folder currently shown on the right, from its root down to
    /// itself -- e.g. GameData > Models > Tower, or Resources > Models > Tower.
    /// `Resources` and `GameData` share the same category names below their own root
    /// (Models, Animations, ...), so this is the only thing that says which tree a
    /// folder deep in either one actually belongs to. GameData has no node of its own
    /// in the sidebar (each category sits directly under the project name), so its
    /// segment is synthesized here; every other root (Resources, a custom folder)
    /// already has one.
    func breadcrumbSegments(for url: URL) -> [BreadcrumbSegment] {
        if let base = assetBasePath?.standardizedFileURL {
            let baseComponents = base.pathComponents
            let comps = url.standardizedFileURL.pathComponents
            if comps.starts(with: baseComponents), comps.count > baseComponents.count,
               let category = AssetCategory(rawValue: comps[baseComponents.count])
            {
                var segments = [BreadcrumbSegment(name: "GameData", url: base, category: nil)]
                var cursor = base
                for component in comps.dropFirst(baseComponents.count) {
                    cursor = cursor.appendingPathComponent(component, isDirectory: true)
                    segments.append(BreadcrumbSegment(name: component, url: cursor, category: category.rawValue))
                }
                return segments
            }
        }

        let namedRoots: [URL] = [resourcesRootURL].compactMap { $0 } + customRootFolders
        if let root = namedRoots.first(where: { candidate in
            let rootPath = candidate.standardizedFileURL.path
            let urlPath = url.standardizedFileURL.path
            return urlPath == rootPath || urlPath.hasPrefix(rootPath + "/")
        }) {
            let rootComponents = root.standardizedFileURL.pathComponents
            let comps = url.standardizedFileURL.pathComponents
            var segments = [BreadcrumbSegment(name: root.lastPathComponent, url: root, category: nil)]
            var cursor = root
            for component in comps.dropFirst(rootComponents.count) {
                cursor = cursor.appendingPathComponent(component, isDirectory: true)
                segments.append(BreadcrumbSegment(name: component, url: cursor, category: nil))
            }
            return segments
        }

        return [BreadcrumbSegment(name: url.lastPathComponent, url: url, category: nil)]
    }

    /// Navigates to a breadcrumb segment the same way clicking its sidebar node would:
    /// `selectDirectory` for a GameData-side category segment (builds the folder chain
    /// down to it), or the generic `selectedDirURL` path for Resources/a custom root.
    func selectBreadcrumb(_ segment: BreadcrumbSegment) {
        navigation.lightsSelected = false
        navigation.primitivesSelected = false
        navigation.entitiesSelected = false
        selectedAsset = nil
        selectedAssetName = nil
        if let category = segment.category {
            selectDirectory(url: segment.url, category: category)
        } else {
            selectedDirURL = segment.url
            selectedCategory = nil
            folderPathStack = []
        }
    }

    func subdirectories(of url: URL) -> [URL] {
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

    func toggleDir(_ url: URL) {
        if expandedDirs.contains(url) {
            expandedDirs.remove(url)
        } else {
            expandedDirs.insert(url)
        }
    }

    func isDirectorySelected(url: URL, category: String) -> Bool {
        guard selectedDirURL == nil else { return false }
        guard selectedCategory == category else { return false }
        guard let current = currentDirectoryURL else { return false }
        return current.standardizedFileURL == url.standardizedFileURL
    }

    func selectDirectory(url: URL, category: String) {
        navigation.lightsSelected = false
        navigation.primitivesSelected = false
        navigation.entitiesSelected = false
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

    /// Brings `folder` into view and highlights `assetName` within it, so a freshly
    /// cooked asset (which can land in a different folder than the source being cooked,
    /// e.g. a model's cook-source folder vs. its category root) is visible right away.
    func navigateToCookedAsset(folder: URL, assetName: String?, category: AssetCategory) {
        selectDirectory(url: folder, category: category.rawValue)
        guard let assetName else { return }
        selectAsset(Asset(name: assetName, category: category.rawValue, path: folder.appendingPathComponent(assetName)))
    }

    /// Entry point for the "New Directory" menu items. If there's no project
    /// asset folder yet, tell the user instead of silently doing nothing.
    func requestNewDirectory(in parent: URL?) {
        guard let parent else {
            showBasePathAlert = true
            return
        }
        createFolder(in: parent)
    }

    /// Create a uniquely-named subfolder inside `parent` (creating `parent` if
    /// needed, e.g. an empty category root) and reveal it.
    func createFolder(in parent: URL) {
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

    func directoryNode(url: URL?, name: String, category: String?, depth: Int) -> AnyView {
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
                    navigation.entitiesSelected = false
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
    var rootDirectoryRow: some View {
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
                navigation.entitiesSelected = false
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
}
