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

    /// Category owning `url` (matched by the top-level folder under the asset
    /// root), used to pick import file types for generic folders.
    func inferCategory(for url: URL?) -> AssetCategory? {
        guard let url, let root = assetBasePath?.standardizedFileURL else { return nil }
        let rootComponents = root.pathComponents
        let comps = url.standardizedFileURL.pathComponents
        guard comps.count > rootComponents.count else { return nil }
        let top = comps[rootComponents.count]
        return AssetCategory(rawValue: top)
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
