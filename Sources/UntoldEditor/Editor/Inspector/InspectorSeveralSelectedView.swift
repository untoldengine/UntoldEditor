//
//  InspectorSeveralSelectedView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The Inspector with several entities selected: how many, and what can be
/// done with them. The properties of one show when it is selected alone.
struct InspectorSeveralSelectedView: View {
    let count: Int

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                square.offset(x: -5, y: -5).foregroundColor(.editorTextDisabled)
                square.offset(x: 5, y: 5).foregroundColor(.editorAccent)
            }
            .frame(width: 44, height: 44)
            Text(Self.title(count: count))
                .font(EditorType.title)
                .foregroundColor(.editorTextSecondary)
            Text("The gizmo moves, turns and scales them together. Click one to see its properties.")
                .font(EditorType.hint)
                .foregroundColor(.editorTextTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 220)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var square: some View {
        RoundedRectangle(cornerRadius: EditorType.Radius.field)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5))
            .frame(width: 32, height: 32)
    }

    static func title(count: Int) -> String {
        "\(count) entities selected"
    }
}
