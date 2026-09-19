//
//  ExploreSceneOverlayView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

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
