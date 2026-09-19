//
//  AssetPackBrowserView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import Foundation
import SwiftUI
import UntoldEngine

struct AssetPackBrowserView: View {
    @Binding var searchQuery: String
    var onAssetsInstalled: () -> Void

    @ObservedObject private var editorBaseAssetPath = EditorAssetBasePath.shared
    @State private var catalogItems: [AssetPackCatalogItem] = []
    @State private var installingItemIds: Set<String> = []
    @State private var installedItemIds: Set<String> = []
    @State private var selectedCategory: String?
    @State private var isLoadingCatalog = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var filteredItems: [AssetPackCatalogItem] {
        filteredAssetPackItems(catalogItems, selectedCategory: selectedCategory, searchQuery: searchQuery)
    }

    private var categoryNames: [String] {
        assetPackCategoryNames(for: catalogItems)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.editorBackground.ignoresSafeArea()

            HStack(spacing: 0) {
                if catalogItems.isEmpty == false {
                    categorySidebar

                    Rectangle()
                        .fill(Color.editorDivider)
                        .frame(width: 1)
                }

                ScrollView(.vertical, showsIndicators: true) {
                    if isLoadingCatalog {
                        ProgressView()
                            .controlSize(.small)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if catalogItems.isEmpty {
                        emptyState
                    } else if filteredItems.isEmpty {
                        Text("No asset packs match the filter")
                            .foregroundColor(.editorTextTertiary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                            ForEach(filteredItems) { item in
                                AssetPackCard(
                                    item: item,
                                    thumbnail: thumbnailImage(for: item),
                                    isInstalled: installedItemIds.contains(item.id),
                                    isInstalling: installingItemIds.contains(item.id),
                                    installAction: { install(item) }
                                )
                            }
                        }
                        .padding(10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(statusIsError ? Color.editorError.opacity(0.85) : Color.editorSuccess.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
            }
        }
        .onAppear(perform: loadCatalog)
        .onChange(of: editorBaseAssetPath.basePath) {
            installedItemIds = []
        }
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Categories")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.editorTextSecondary)
                .padding(.horizontal, 10)
                .padding(.top, 10)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 3) {
                    categoryButton(title: "All", count: catalogItems.count, isSelected: selectedCategory == nil) {
                        selectedCategory = nil
                    }

                    ForEach(categoryNames, id: \.self) { category in
                        categoryButton(
                            title: category,
                            count: catalogItems.filter { assetPackCategoryName(for: $0) == category }.count,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = category
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }
        }
        .frame(width: 176)
        .background(Color.editorSurface.opacity(0.36))
    }

    private func categoryButton(
        title: String,
        count: Int,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .editorTextPrimary : .editorTextSecondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.editorTextTertiary)
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(isSelected ? Color.editorAccent.opacity(0.22) : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No asset packs available")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.editorTextPrimary)
            Text("Check your connection and try again.")
                .font(.system(size: 12))
                .foregroundColor(.editorTextSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadCatalog() {
        if isLoadingCatalog || catalogItems.isEmpty == false {
            return
        }

        guard let catalogURL = configuredAssetPackCatalogURL() else {
            let catalog = defaultAssetPackCatalog()
            catalogItems = catalog.assets
            reconcileSelectedCategory()
            return
        }

        isLoadingCatalog = true
        Task {
            do {
                let catalog = try await fetchAssetPackCatalog(from: catalogURL)
                await MainActor.run {
                    catalogItems = catalog.assets
                    isLoadingCatalog = false
                    reconcileSelectedCategory()
                }
            } catch {
                await MainActor.run {
                    let catalog = defaultAssetPackCatalog()
                    catalogItems = catalog.assets
                    isLoadingCatalog = false
                    reconcileSelectedCategory()
                    showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func reconcileSelectedCategory() {
        guard let selectedCategory else { return }
        if categoryNames.contains(selectedCategory) == false {
            self.selectedCategory = nil
        }
    }

    private func install(_ item: AssetPackCatalogItem) {
        guard installingItemIds.contains(item.id) == false else { return }
        installingItemIds.insert(item.id)
        showStatus("Installing \(item.name)...")
        let trackedTask = TaskCenter.begin(
            "Installing \(item.name)",
            detail: "Checking local cache..."
        )

        Task {
            do {
                let result = try await installAssetPack(item, into: editorBaseAssetPath.basePath, task: trackedTask)
                await MainActor.run {
                    installingItemIds.remove(item.id)
                    installedItemIds.insert(item.id)
                    onAssetsInstalled()
                    Logger.log(message: "Installed asset pack \(item.name) into GameData.")
                    let source = result.source == .cache ? "from cache" : "from download"
                    trackedTask.succeed("Installed \(result.fileCount) file\(result.fileCount == 1 ? "" : "s") \(source)")
                    showStatus("Installed \(result.fileCount) file\(result.fileCount == 1 ? "" : "s") \(source)")
                }
            } catch {
                await MainActor.run {
                    installingItemIds.remove(item.id)
                    trackedTask.fail(error.localizedDescription)
                    showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    private func thumbnailImage(for item: AssetPackCatalogItem) -> NSImage? {
        guard let thumbnailName = item.thumbnailName else {
            return nil
        }

        return Bundle.editorThumbnailImage(
            forResource: thumbnailName,
            extensions: ["png"],
            bundleName: "UntoldEditor_UntoldEditor.bundle",
            context: "AssetPackBrowserView"
        )
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }
}
