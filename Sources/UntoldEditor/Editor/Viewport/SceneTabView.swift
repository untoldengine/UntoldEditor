//
//  SceneTabView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One scene tab: the loaded scene sits in front on the window's colour with a
/// hairline; the others are plain text. The dot marks unsaved changes.
struct SceneTabView: View {
    let tab: SceneTab
    let onSelect: () -> Void

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: EditorType.Radius.field, topTrailingRadius: EditorType.Radius.field)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(tab.name)
                    .font(tab.isActive ? EditorType.title : EditorType.body)
                    .foregroundColor(tab.isActive ? .editorTextPrimary : .editorTextSecondary)
                    .lineLimit(1)
                if tab.isDirty {
                    Circle()
                        .fill(Color.editorAccent)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(tab.isActive ? Color.editorBackground : Color.clear, in: shape)
            .overlay {
                if tab.isActive {
                    shape.stroke(Color.editorHairline, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(tab.isActive ? "The loaded scene" : "Load this scene")
    }
}
