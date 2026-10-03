//
//  ViewportNavigationCluster.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The navigation controls at the top right of the viewport: the gizmo, and
/// under it the buttons that zoom and pan while they are dragged.
struct ViewportNavigationCluster: View {
    let handles: [NavigationGizmoHandle]
    let onSelectView: (ViewportProjection) -> Void

    var body: some View {
        VStack(spacing: 8) {
            NavigationGizmoView(handles: handles, onSelectView: onSelectView, orbit: .camera(.orbit))
            NavigationDragButton(
                systemImage: "magnifyingglass",
                help: "Zoom: drag up or right to move closer, down or left to move away",
                handlers: .camera(.zoom)
            )
            NavigationDragButton(
                systemImage: "hand.raised",
                help: "Pan: drag to slide the view",
                handlers: .camera(.pan)
            )
        }
        // The keys keep flying the camera with the pointer over these controls.
        .onHover { InputSystem.shared.pointerIsOverViewportControl($0) }
        .onDisappear { InputSystem.shared.pointerIsOverViewportControl(false) }
    }
}
