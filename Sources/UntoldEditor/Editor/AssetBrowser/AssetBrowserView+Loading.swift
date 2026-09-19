//
//  AssetBrowserView+Loading.swift
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
    // MARK: - Load Assets

    func loadAssets() {
        guard editorBaseAssetPath.basePath != nil else { return }
        guard let basePath = assetBasePath else { return }

        var groupedAssets: [String: [Asset]] = [:]

        for category in AssetCategory.allCases {
            let categoryPath = basePath.appendingPathComponent(category.rawValue, isDirectory: true)
            var categoryAssets: [Asset] = []

            if category == .scripts {
                // Flat list of .uscript files anywhere under Scripts
                let uscriptURLs = findFilesRecursively(at: categoryPath, withExtension: "uscript")
                for url in uscriptURLs {
                    categoryAssets.append(
                        Asset(name: url.lastPathComponent,
                              category: category.rawValue,
                              path: url,
                              isFolder: false)
                    )
                }
                // Sort for stable UI
                categoryAssets.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                groupedAssets[category.rawValue] = categoryAssets
                continue
            }

            // Non-Scripts categories: list immediate children, with folder navigation support
            if let contents = try? FileManager.default.contentsOfDirectory(
                at: categoryPath,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) {
                for item in contents {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir) {
                        if isDir.boolValue {
                            // It’s a folder — valid for all categories
                            categoryAssets.append(Asset(name: item.lastPathComponent,
                                                        category: category.rawValue,
                                                        path: item,
                                                        isFolder: true))
                        } else if category == .hdr {
                            // For HDR, also allow .hdr and .exr files directly in the HDR folder
                            if ["hdr", "exr"].contains(item.pathExtension.lowercased()) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .lut {
                            if item.pathExtension.lowercased() == "cube" {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .gaussians {
                            // For Gaussians, allow gaussian files directly in the Gaussians folder
                            categoryAssets.append(Asset(name: item.lastPathComponent,
                                                        category: category.rawValue,
                                                        path: item,
                                                        isFolder: false))
                        } else if category == .models || category == .animations {
                            if runtimeAssetExtensions(for: category).contains(item.pathExtension.lowercased()) || sourceAssetExtensions.contains(item.pathExtension.lowercased()) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .scripts {
                            // Not used anymore due to flat listing, but keep for safety (won’t execute due to continue above)
                        } else if category == .streamModels {
                            if item.pathExtension.lowercased() == "json", isTiledSceneManifest(item) {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            } else if item.pathExtension.lowercased() == "remotestream" {
                                categoryAssets.append(Asset(name: item.deletingPathExtension().lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        } else if category == .scenes {
                            // For Scenes, allow files directly in the Scenes folder
                            if item.pathExtension.lowercased() == untoldSceneFileExtension {
                                categoryAssets.append(Asset(name: item.lastPathComponent,
                                                            category: category.rawValue,
                                                            path: item,
                                                            isFolder: false))
                            }
                        }
                    }
                }
            }

            groupedAssets[category.rawValue] = categoryAssets
        }

        assets = groupedAssets
    }

    func matchesSearch(_ asset: Asset) -> Bool {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        return asset.name.localizedCaseInsensitiveContains(query)
    }

    func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    /// Recursively find all files with a specific extension under a root directory
    func findFilesRecursively(at root: URL, withExtension ext: String) -> [URL] {
        var results: [URL] = []
        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == ext.lowercased() {
                results.append(url)
            }
        }

        return results
    }
}
