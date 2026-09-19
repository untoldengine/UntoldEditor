//
//  DemoSceneCard.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

struct DemoSceneCard: View {
    let demo: DemoSceneCatalogItem
    var onSelect: () -> Void

    private var thumbnailImage: NSImage? {
        Bundle.editorThumbnailImage(
            forResource: demo.thumbnailName,
            extensions: ["png", "jpg", "jpeg"],
            bundleName: "UntoldEditor_UntoldEditor.bundle",
            context: "DemoSceneCard"
        )
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
