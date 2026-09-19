//
//  QuickPreviewSceneOverlayView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

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
