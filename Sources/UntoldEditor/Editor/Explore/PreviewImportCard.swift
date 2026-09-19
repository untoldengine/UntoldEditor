//
//  PreviewImportCard.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

struct PreviewImportCard: View {
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
