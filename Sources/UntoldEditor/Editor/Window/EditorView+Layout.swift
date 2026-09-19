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
    /// change so the viewport doesn't compete with the layout change (which
    /// caused stutter). Called when the docking layout changes, so it covers
    /// every trigger: tab strips, the menus (⌘1/2/3) and Focus Viewport (⌘F).
    /// The viewport freezes on a screen-sized frame trimmed to the changing
    /// size (see EditorViewportResizePolicy), then resumes.
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

    /// The render loop holds while a docking divider drags, as it does during
    /// a window resize: the frozen frame is trimmed, not stretched.
    func beginViewportResizeHold() {
        guard let view = renderer?.metalView else { return }
        EditorViewportResizePolicy.beginResizeHold(of: view)
    }

    func endViewportResizeHold() {
        guard let view = renderer?.metalView else { return }
        EditorViewportResizePolicy.endResizeHold(of: view)
    }
}
