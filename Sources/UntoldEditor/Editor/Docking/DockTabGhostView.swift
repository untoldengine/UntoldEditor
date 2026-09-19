//
//  DockTabGhostView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The pill that follows the pointer while a tab drags, with the panel's
/// title; the tab itself stays in its strip until the drop.
struct DockTabGhostView: View {
    let drag: DockTabDrag?

    var body: some View {
        GeometryReader { _ in
            if let drag {
                Text(drag.panel.title)
                    .font(EditorType.title)
                    .foregroundColor(.editorTextPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Color.editorControlActive)
                    .cornerRadius(EditorType.Radius.field)
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorType.Radius.field)
                            .stroke(Color.editorAccent, lineWidth: 1)
                    )
                    .shadow(color: Color.editorShadowStrong, radius: 6, x: 0, y: 2)
                    .position(x: drag.location.x, y: drag.location.y)
            }
        }
        .allowsHitTesting(false)
    }
}
