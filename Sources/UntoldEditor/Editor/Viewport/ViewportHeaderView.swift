//
//  ViewportHeaderView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The 36 pt row above the Metal view: the interaction mode, the tools, and
/// at the right the shading, the projection and the camera speed.
struct ViewportHeaderView: View {
    static let height: CGFloat = 36

    @ObservedObject var settings: EditorViewportSettings
    let onSelectTool: (TransformTool) -> Void
    let onSelectShading: (ViewportShading) -> Void
    let onSelectProjection: (ViewportProjection) -> Void

    var body: some View {
        HStack(spacing: 8) {
            InteractionModeMenu(mode: settings.interactionMode)
            divider
            ViewportToolCluster(tool: settings.tool, onSelect: onSelectTool)
            Spacer(minLength: 8)
            ViewportShadingMenu(shading: settings.shading, onSelect: onSelectShading)
            ViewportProjectionMenu(projection: settings.projection, onSelect: onSelectProjection)
            CameraSpeedControl(speed: $settings.cameraSpeed)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color.editorViewportHeader)
        .overlay(alignment: .bottom) {
            Color.editorHairline.frame(height: 1)
        }
    }

    private var divider: some View {
        Color.editorDivider.frame(width: 1, height: 20)
    }
}
