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
