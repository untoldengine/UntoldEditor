//
//  DemoGalleryView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

struct DemoGalleryView: View {
    let demos: [DemoSceneCatalogItem]
    var onDemoSelected: (DemoSceneCatalogItem) -> Void
    var onTryOwnScene: () -> Void
    var onCreateProject: () -> Void
    var onOpenProject: () -> Void
    var onOpenFullEditor: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 190), spacing: 14, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                    ForEach(demos) { demo in
                        DemoSceneCard(demo: demo) {
                            onDemoSelected(demo)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 420)

            footer
        }
        .padding(20)
        .frame(maxWidth: 760)
        .background(
            LinearGradient(
                colors: [
                    Color.editorPanelBackground.opacity(0.98),
                    Color.editorBackground.opacity(0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(14)
        .shadow(color: .editorShadowStrong, radius: 24, x: 0, y: 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Explore Untold Engine")
                    .font(.largeTitle.bold())
                    .foregroundColor(.editorTextPrimary)

                Text("Open a ready-to-navigate scene. No project setup, asset import, or scene graph knowledge required.")
                    .font(.body)
                    .foregroundColor(.editorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onOpenFullEditor) {
                Label("Full Editor", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .tint(Color.editorSecondaryAccent)
            .focusable(false)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onTryOwnScene) {
                Label("Try Your Own Scene", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.editorAccent)
            .focusable(false)
            Button(action: onCreateProject) {
                Label("Create Project", systemImage: "hammer.fill")
            }
            .focusable(false)

            Button(action: onOpenProject) {
                Label("Open Project", systemImage: "folder.fill")
            }
            .focusable(false)

            Spacer()

            Text("You can switch to the full editor after loading a scene.")
                .font(.caption)
                .foregroundColor(.editorTextTertiary)
        }
    }
}

struct PreviewImportGalleryView: View {
    var onModeSelected: (QuickPreviewImportMode) -> Void
    var onBackToDemos: () -> Void
    var onOpenFullEditor: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: 14, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(QuickPreviewImportMode.allCases, id: \.self) { mode in
                    PreviewImportCard(mode: mode) {
                        onModeSelected(mode)
                    }
                }
            }

            preparationGuide
        }
        .padding(20)
        .frame(maxWidth: 760)
        .background(
            LinearGradient(
                colors: [
                    Color.editorPanelBackground.opacity(0.98),
                    Color.editorBackground.opacity(0.98),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(14)
        .shadow(color: .editorShadowStrong, radius: 24, x: 0, y: 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Try Your Own Scene")
                    .font(.largeTitle.bold())
                    .foregroundColor(.editorTextPrimary)

                Text("Load an exported Untold scene file without creating a project. You can navigate immediately, then open the full editor when you are ready.")
                    .font(.body)
                    .foregroundColor(.editorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Back to Demos", action: onBackToDemos)
                .buttonStyle(.bordered)
                .tint(Color.editorSecondaryAccent)
                .focusable(false)

            Button(action: onOpenFullEditor) {
                Label("Full Editor", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .tint(Color.editorSecondaryAccent)
            .focusable(false)
        }
    }

    private var preparationGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Need to create one of these files?", systemImage: "wand.and.stars")
                .font(.headline)
                .foregroundColor(.editorTextPrimary)

            Text("Export from Blender with the Untold exporter add-on, or use the CLI exporter to produce .untold runtime assets and tiled .json scene manifests. Gaussian splats can be loaded from .ply files or baked .untoldgs files.")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Link(
                "Get the Blender add-on and installation steps",
                destination: URL(string: "https://untoldengine.github.io/UntoldEngine/API/UsingBlenderAddon/")!
            )
            .font(.caption.weight(.semibold))
            .foregroundColor(Color.editorAccent)
            .focusable(false)

            HStack(spacing: 8) {
                Text("1. Install Blender")
                Text("2. Install Untold exporter")
                Text("3. Export")
                Text("4. Load here")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.editorTextSecondary)
        }
        .padding(12)
        .background(Color.editorSurface.opacity(0.56))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

private struct PreviewImportCard: View {
    let mode: QuickPreviewImportMode
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.editorAccentSoft)

                    Image(systemName: mode.systemImageName)
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundColor(.editorTextPrimary)
                }
                .frame(height: 96)

                Text(mode.exploreTitle)
                    .font(.headline)
                    .foregroundColor(.editorTextPrimary)

                Text(mode.exploreSubtitle)
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(mode.exploreFileTypes)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.editorTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.editorBadgeBackground)
                    .cornerRadius(7)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.editorSurface.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.editorDivider, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

struct QuickPreviewSceneOverlayView: View {
    let title: String
    let mode: QuickPreviewImportMode?
    var onLoadAnother: () -> Void
    var onChooseDemo: () -> Void
    var onOpenFullEditor: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.editorTextPrimary)
                Text(mode?.exploreLoadedSubtitle ?? "Your Scene")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            }

            Spacer()

            Button("Load Another", action: onLoadAnother)
                .focusable(false)
            Button("Demo Gallery", action: onChooseDemo)
                .focusable(false)
            Button(action: onOpenFullEditor) {
                Label("Full Editor", systemImage: "slider.horizontal.3")
            }
            .focusable(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.editorPanelBackground.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: .editorShadow, radius: 14, x: 0, y: 8)
    }
}

private extension QuickPreviewImportMode {
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

private struct DemoSceneCard: View {
    let demo: DemoSceneCatalogItem
    var onSelect: () -> Void

    private var thumbnailImage: NSImage? {
        for ext in ["png", "jpg", "jpeg"] {
            if let url = Bundle.module.url(forResource: demo.thumbnailName, withExtension: ext),
               let img = NSImage(contentsOf: url)
            {
                return img
            }
        }
        return nil
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.editorAccentSoft,
                                    Color.editorSecondaryAccent.opacity(0.18),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if let img = thumbnailImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    } else {
                        Image(systemName: demo.systemImageName)
                            .font(.system(size: 42, weight: .semibold))
                            .foregroundColor(.editorTextPrimary)
                    }
                }
                .frame(height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(demo.title)
                        .font(.headline)
                        .foregroundColor(.editorTextPrimary)

                    Text(demo.subtitle)
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                tagRow
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.editorSurface.opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.editorDivider, lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var tagRow: some View {
        HStack(spacing: 6) {
            ForEach(demo.tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.editorTextSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.editorBadgeBackground)
                    .cornerRadius(7)
            }
        }
    }
}

struct ExploreSceneOverlayView: View {
    let demo: DemoSceneCatalogItem
    var onChooseAnotherDemo: () -> Void
    var onResetCamera: () -> Void
    var onOpenFullEditor: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(demo.title)
                    .font(.headline)
                    .foregroundColor(.editorTextPrimary)
                Text("Explore Mode")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            }

            Spacer()

            Button("Choose Another Demo", action: onChooseAnotherDemo)
                .focusable(false)
            Button("Reset View", action: onResetCamera)
                .focusable(false)
            Button(action: onOpenFullEditor) {
                Label("Full Editor", systemImage: "slider.horizontal.3")
            }
            .focusable(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.editorPanelBackground.opacity(0.92))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(10)
        .shadow(color: .editorShadow, radius: 14, x: 0, y: 8)
    }
}
