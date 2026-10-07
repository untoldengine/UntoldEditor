//
//  VisionProPreviewLabel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The label over the viewport while the scene is previewed on a headset:
/// what is going on, how the keys fly, and the way to stop.
struct VisionProPreviewLabel: View {
    let state: VisionProPreviewSession.State
    let onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "visionpro")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.editorAccent)
            Text(state == .connecting ? "Connecting to Apple Vision Pro" : "Previewing on Apple Vision Pro")
                .font(EditorType.badge)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Text(state == .connecting ? "Accept on the headset" : "Drawn by this Mac")
                .font(EditorType.hint)
                .foregroundColor(.editorTextTertiary)
                .fixedSize()
            Color.editorDivider.frame(width: 1, height: 14)
            Button(action: onStop) {
                Text("Stop")
                    .font(EditorType.badge)
                    .foregroundColor(.editorAccent)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Ends the preview; the viewport goes back to the editor's camera")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.editorScrim)
        .overlay(
            RoundedRectangle(cornerRadius: EditorType.Radius.card)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(EditorType.Radius.card)
        .help("The scene shows in the Apple Vision Pro, drawn by this Mac; the viewport shows the headset's left eye. The panels still edit the scene; the viewport takes no camera or scene input until the preview ends.")
    }
}
