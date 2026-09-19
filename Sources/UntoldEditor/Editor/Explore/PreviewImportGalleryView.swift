//
//  PreviewImportGalleryView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

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
