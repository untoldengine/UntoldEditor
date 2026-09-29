//
//  ViewportCameraLabel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The label over the viewport while it is a locked preview of a game camera:
/// which camera is shown, that the view is locked, and the way back to the
/// editor's camera.
struct ViewportCameraLabel: View {
    let cameraName: String
    let onShowEditorCamera: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "video.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.editorAccent)
            Text(cameraName)
                .font(EditorType.badge)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Text("Locked preview")
                .font(EditorType.hint)
                .foregroundColor(.editorTextTertiary)
                .fixedSize()
            Color.editorDivider.frame(width: 1, height: 14)
            Button(action: onShowEditorCamera) {
                Text("Editor Camera")
                    .font(EditorType.badge)
                    .foregroundColor(.editorAccent)
                    .fixedSize()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Back to the editor's camera, which the mouse and the keys move")
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Color.editorScrim)
        .overlay(
            RoundedRectangle(cornerRadius: EditorType.Radius.card)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(EditorType.Radius.card)
        .help("The viewport shows the game camera \(cameraName). Nothing moves until the editor's camera is chosen again.")
    }
}
