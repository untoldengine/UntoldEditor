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
/// statistics at the top left, the navigation controls at the top right and
/// the shortcut hints along the bottom. Only the navigation controls take the
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

    static let margin: CGFloat = 12

    var body: some View {
        ZStack {
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
                ViewportHintChips(hints: ViewportHints.hints(style: navigation.style, hasSelection: hasSelection))
                    .padding(Self.margin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
    }
}
