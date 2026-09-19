//
//  EditorPopupMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The card of a custom dropdown menu, for menus a native `Menu` cannot draw:
/// rows with subtitles and shortcuts (the interaction mode menu) or rows that
/// are steppers and toggles (the snap menu). Radius 8, the panel background, a
/// hairline and the strong shadow. Present it from the opening control with
/// `.popover`; fill it with `EditorPopupMenuRow`s or any content.
struct EditorPopupMenu<Content: View>: View {
    private let width: CGFloat
    private let content: Content

    init(width: CGFloat = 220, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(4)
        .frame(width: width)
        .background(Color.editorPanelBackground)
        .cornerRadius(EditorType.Radius.card)
        .overlay(
            RoundedRectangle(cornerRadius: EditorType.Radius.card)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .shadow(color: Color.editorShadowStrong, radius: 15, x: 0, y: 10)
    }
}
