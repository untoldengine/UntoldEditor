//
//  TransformModeCluster.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation
import SwiftUI
import UntoldEngine

/// Compact translate/rotate/scale cluster designed to float inside the scene
/// viewport (bottom-left corner) instead of sitting in a full-width toolbar.
struct TransformModeCluster: View {
    @ObservedObject var controller: EditorController

    var body: some View {
        HStack(spacing: 4) {
            ModeButton(
                icon: "arrow.up.and.down.and.arrow.left.and.right",
                label: "Translate",
                mode: .translate,
                activeMode: $controller.activeMode
            )
            ModeButton(
                icon: "rotate.3d",
                label: "Rotate",
                mode: .rotate,
                activeMode: $controller.activeMode
            )
            ModeButton(
                icon: "arrow.up.left.and.down.right.magnifyingglass",
                label: "Scale",
                mode: .scale,
                activeMode: $controller.activeMode
            )
        }
        .padding(4)
        .background(Color.editorPanelBackground.opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .shadow(color: Color.editorShadow, radius: 6, x: 0, y: 2)
    }
}
