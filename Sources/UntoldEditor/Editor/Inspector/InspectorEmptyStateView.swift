//
//  InspectorEmptyStateView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The Inspector with nothing selected: a dashed square and how to select something.
struct InspectorEmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: EditorType.Radius.field)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundColor(.editorTextDisabled)
                .frame(width: 44, height: 44)
            Text("No entity selected")
                .font(EditorType.title)
                .foregroundColor(.editorTextSecondary)
            Text("Click an entity in the viewport or Hierarchy. Drag a model from Assets to place it.")
                .font(EditorType.hint)
                .foregroundColor(.editorTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
