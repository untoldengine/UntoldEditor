//
//  EditorPillMenuButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A text button inside an `EditorPillGroup` that opens a menu or a popover: an
/// optional glyph, the title and a small chevron, 26 pt, with no fill of its own
/// so the group's pill is the surface. History and the build target use it.
struct EditorPillMenuButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(EditorType.body)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(isEnabled ? Color.editorTextPrimary : Color.editorTextDisabled)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isEnabled == false)
        .help(help)
    }
}
