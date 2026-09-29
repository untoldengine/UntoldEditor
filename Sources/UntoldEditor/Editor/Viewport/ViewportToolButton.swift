//
//  ViewportToolButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One tool of the viewport header: 28 by 24, the glyph on the accent while
/// the tool is active.
struct ViewportToolButton: View {
    let tool: TransformTool
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isActive ? .editorTextInverse : .editorTextSecondary)
                .frame(width: 28, height: 24)
                .background(isActive ? Color.editorAccent : Color.clear)
                .cornerRadius(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("\(tool.title) (\(tool.shortcut))")
    }
}
