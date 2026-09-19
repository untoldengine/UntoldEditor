//
//  EditorPillButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One button of an `EditorPillGroup`: a glyph on a 28×26 pt rounded surface.
/// Active draws the accent fill with an inverse glyph; disabled draws the glyph
/// in the disabled text color and ignores clicks.
struct EditorPillButton: View {
    let systemImage: String
    var isActive = false
    var isEnabled = true
    var help = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Self.glyphColor(isActive: isActive, isEnabled: isEnabled))
                .frame(width: 28, height: 26)
                .background(isActive ? Color.editorAccent : Color.clear)
                .cornerRadius(EditorType.Radius.button)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(isEnabled == false)
        .help(help)
    }

    /// The glyph color for a state: disabled wins over active.
    static func glyphColor(isActive: Bool, isEnabled: Bool) -> Color {
        if isEnabled == false {
            return .editorTextDisabled
        }
        return isActive ? .editorTextInverse : .editorTextPrimary
    }
}
