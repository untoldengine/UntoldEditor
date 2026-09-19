//
//  EditorPillGroup.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The grouped pill of the toolbar and the viewport header: a dark capsule with
/// radius 7 holding `EditorPillButton`s, or any other 26 pt controls, side by side.
struct EditorPillGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 2, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
        .padding(3)
        .background(Color.editorBadgeBackground)
        .cornerRadius(EditorType.Radius.pill)
    }
}
