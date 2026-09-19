//
//  CameraControlHintsView.swift
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

struct CameraControlHintsView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Camera Controls", systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.editorTextPrimary)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Dismiss")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Two-finger drag to orbit", systemImage: "arrow.triangle.2.circlepath")
                Label("Scroll or pinch to zoom", systemImage: "magnifyingglass")
                Label("WASD moves, Q/E raises and lowers", systemImage: "keyboard")
            }
            .font(.caption)
            .foregroundColor(.editorTextSecondary)
            .labelStyle(.titleAndIcon)
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(Color.editorPanelBackground.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: .editorShadow, radius: 12, x: 0, y: 6)
    }
}
