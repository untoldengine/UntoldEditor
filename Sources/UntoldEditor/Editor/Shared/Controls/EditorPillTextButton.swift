//
//  EditorPillTextButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// A text button inside an `EditorPillGroup` that does something at once: an
/// optional glyph and the title, 26 pt, lit in the accent colour while what it
/// started goes on, with no fill of its own so the group's pill is the surface.
/// The preview control uses it.
struct EditorPillTextButton: View {
    let title: String
    var systemImage: String?
    var isActive = false
    var isEnabled = true
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title)
                    .font(EditorType.body)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isEnabled == false)
        .help(help)
    }

    private var color: Color {
        if isEnabled == false {
            return Color.editorTextDisabled
        }
        return isActive ? Color.editorAccent : Color.editorTextPrimary
    }
}
