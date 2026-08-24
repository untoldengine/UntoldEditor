//
//  TransformManipulationView.swift
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

struct ModeButton: View {
    let icon: String
    let label: String
    let mode: TransformManipulationMode
    @Binding var activeMode: TransformManipulationMode

    var isActive: Bool {
        activeMode == mode
    }

    var body: some View {
        Button(action: {
            if gizmoActive == false {
                return
            }

            if activeMode == mode {
                activeMode = .none
            } else {
                activeMode = mode

                if activeMode == .translate {
                    createGizmo(name: "translateGizmo")
                } else if activeMode == .rotate {
                    createGizmo(name: "rotateGizmo")
                } else if activeMode == .scale {
                    createGizmo(name: "scaleGizmo")
                }
            }
        }) {
            HStack {
                Image(systemName: icon)
                // Text(label)
            }
            .padding(8)
            .background(isActive ? Color.editorAccentSoft : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

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

struct TransformManipulationToolbar: View {
    @ObservedObject var controller: EditorController

    var body: some View {
        HStack {
            Spacer()

            // Centered mode buttons
            HStack(spacing: 5) {
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

            Spacer()
        }
        .padding(.horizontal)
        .background(Color.editorFill)
        .cornerRadius(5)
    }
}
