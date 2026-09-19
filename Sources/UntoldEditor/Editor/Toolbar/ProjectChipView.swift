//
//  ProjectChipView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The project chip at the left of the toolbar: the orange project mark, the
/// project's name and the editor version. Clicking it selects the project, which
/// shows the Environment and Effects editors in the right panel.
struct ProjectChipView: View {
    let projectName: String?
    let version: String
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.editorAccent)
                    .frame(width: 16, height: 12)
                Text(projectName ?? "No project")
                    .font(EditorType.toolbar)
                    .foregroundColor(.editorTextPrimary)
                    .lineLimit(1)
                Text("· Untold Editor v\(version)")
                    .font(EditorType.body)
                    .foregroundColor(.editorTextSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(projectName == nil)
        .help(projectName == nil ? "Create or open a project from the File menu" : "Select the project to edit its environment and effects")
    }
}
