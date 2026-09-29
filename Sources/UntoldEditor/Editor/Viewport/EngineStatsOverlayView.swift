//
//  EngineStatsOverlayView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import SwiftUI
import UntoldEngine

/// The frame statistics over the viewport, under the mode badge: two compact
/// lines, or every number the engine reports when View > Show FPS Advanced
/// asks for them. Clicks go through it to the scene.
struct EngineStatsOverlayView: View {
    @ObservedObject private var store = EditorEngineStatsStore.shared

    var body: some View {
        switch store.overlayMode {
        case .off:
            EmptyView()
        case .simplified:
            card {
                Text(EngineStatsCompactText.timing(frameMs: store.snapshot.timing.smoothedFrameMs))
                Text(EngineStatsCompactText.drawn(
                    triangles: store.snapshot.render.trianglesTotal,
                    drawCalls: store.snapshot.render.drawCallsTotal
                ))
            }
        case .advanced:
            card {
                Text(formatEngineStatsOverlay(store.snapshot))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(@ViewBuilder lines: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            lines()
        }
        .font(EditorType.mono)
        .foregroundColor(.editorTextPrimary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.editorScrim)
        .cornerRadius(EditorType.Radius.field)
        .allowsHitTesting(false)
    }
}
