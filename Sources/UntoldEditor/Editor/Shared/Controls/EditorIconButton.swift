//
//  EditorIconButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A small icon button: the round scrim buttons floating over the viewport
/// (zoom, pan, camera view) or the plain `+` and `⋯` buttons of a panel header.
struct EditorIconButton: View {
    enum Style {
        /// A round scrim behind the glyph, for buttons over the scene.
        case scrim
        /// No background, for buttons inside chrome.
        case plain
    }

    let systemImage: String
    var style: Style = .plain
    var size: CGFloat = 26
    var isActive = false
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? Color.editorAccent : Color.editorTextPrimary)
                .frame(width: size, height: size)
                .background(style == .scrim ? Color.editorScrim : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
