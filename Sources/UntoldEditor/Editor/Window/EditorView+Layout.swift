//
//  EditorView+Layout.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    /// Pause the Metal render loop for the duration of a panel show/hide
    /// animation so the viewport doesn't compete with the layout change (which
    /// caused stutter). Called from onChange, so it covers every trigger: edge
    /// tabs, the View menu (⌘1/2/3) and Focus Viewport (⌘F). The viewport freezes
    /// on a screen-sized frame trimmed to the changing size (see
    /// EditorViewportResizePolicy), then resumes.
    func pauseRenderForPanelAnimation() {
        guard let view = renderer?.metalView else { return }
        EditorViewportResizePolicy.beginResizeHold(of: view)
        renderPauseGeneration += 1
        let generation = renderPauseGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + panelAnimationDuration + 0.05) {
            if generation == renderPauseGeneration {
                EditorViewportResizePolicy.endResizeHold(of: view)
            }
        }
    }

    /// Small always-visible tab that protrudes from a panel's inner edge (placed
    /// as an overlay above the viewport) to collapse/expand the panel.
    func panelEdgeTabVertical(
        isOpen: Bool,
        openIcon: String,
        closedIcon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: isOpen ? openIcon : closedIcon)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.editorTextSecondary)
                .frame(width: 16, height: 48)
                .background(Color.editorPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
                .shadow(color: Color.editorShadow, radius: 4, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }

    func panelEdgeTabHorizontal(
        isOpen: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.editorTextSecondary)
                .frame(width: 48, height: 16)
                .background(Color.editorPanelBackground)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
                .shadow(color: Color.editorShadow, radius: 4, x: 0, y: 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
