//
//  DemoGalleryView.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import SwiftUI

struct DemoGalleryView: View {
    let demos: [DemoSceneCatalogItem]
    var onDemoSelected: (DemoSceneCatalogItem) -> Void
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
        .shadow(color: .black.opacity(0.34), radius: 24, x: 0, y: 14)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Explore Untold Engine")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)

                Text("Open a ready-to-navigate scene. No project setup, asset import, or scene graph knowledge required.")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.78))
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
            Button(action: onCreateProject) {
                Label("Create Project", systemImage: "hammer.fill")
            }
            .focusable(false)

            Button(action: onOpenProject) {
                Label("Open Project", systemImage: "folder.fill")
            }
            .focusable(false)

            Spacer()

            Text("You can switch to the full editor after loading a demo.")
                .font(.caption)
                .foregroundColor(.white.opacity(0.58))
        }
    }
}

private struct DemoSceneCard: View {
    let demo: DemoSceneCatalogItem
    var onSelect: () -> Void

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

                    Image(systemName: demo.systemImageName)
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundColor(.white.opacity(0.88))
                }
                .frame(height: 112)

                VStack(alignment: .leading, spacing: 6) {
                    Text(demo.title)
                        .font(.headline)
                        .foregroundColor(.white)

                    Text(demo.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.68))
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
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                    .foregroundColor(.white.opacity(0.74))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.18))
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
                    .foregroundColor(.white)
                Text("Explore Mode")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.66))
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
        .shadow(color: .black.opacity(0.25), radius: 14, x: 0, y: 8)
    }
}
