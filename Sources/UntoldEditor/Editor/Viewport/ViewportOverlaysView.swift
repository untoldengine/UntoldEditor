//
//  ViewportOverlaysView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// What the editor draws over the scene: the mode badge and the frame
/// statistics at the top left, the navigation controls at the top right, the
/// shortcut hints along the bottom, and the rectangle while one is dragged
/// to select what is inside it. Only the navigation controls take the
/// pointer; everywhere else a click reaches the scene.
struct ViewportOverlaysView: View {
    /// True while the viewport shows the editor's camera for editing: the
    /// badge and the navigation controls are the editor's.
    let showsEditorOverlays: Bool
    let showsStats: Bool
    let showsHints: Bool
    /// The room a bar of the editor takes along the top of the viewport, as
    /// the one of explore mode does; the top left corner starts below it.
    var topInset: CGFloat = 0
    let mode: InteractionMode
    let hasSelection: Bool
    let onSelectView: (ViewportProjection) -> Void

    @ObservedObject var overlays = EditorViewportOverlaySettings.shared
    @ObservedObject var store = ViewportOverlayStore.shared
    @ObservedObject var navigation = EditorNavigationSettings.shared
    @ObservedObject var marquee = ViewportMarqueeStore.shared

    static let margin: CGFloat = 12

    /// Selecting is hinted where the editor's overlays show: there the
    /// viewport selects.
    private var hints: [ViewportHint] {
        ViewportHints.hints(style: navigation.style, hasSelection: hasSelection, canSelect: showsEditorOverlays)
    }

    var body: some View {
        ZStack {
            if showsEditorOverlays, let rect = marquee.rect {
                MarqueeView(rect: rect)
            }

            VStack(alignment: .leading, spacing: 6) {
                if showsEditorOverlays, overlays.isShown(.modeBadge) {
                    ModeBadgeView(mode: mode)
                }
                if showsStats {
                    EngineStatsOverlayView()
                }
            }
            .padding(Self.margin)
            .padding(.top, topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if showsEditorOverlays, overlays.isShown(.navigationGizmo), store.handles.isEmpty == false {
                ViewportNavigationCluster(handles: store.handles, onSelectView: onSelectView)
                    .padding(Self.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if showsHints, overlays.isShown(.hints) {
                ViewportHintChips(hints: hints)
                    .padding(Self.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
