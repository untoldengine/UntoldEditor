//
//  EditorSegmented.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A small segmented control (24 pt): text segments side by side on the control
/// fill, the selected one raised on the active surface. World / Local and the
/// grid / list switch of the asset browser are the two in the mockups.
struct EditorSegmented<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var help: (Option) -> String = { _ in "" }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(EditorType.body)
                        .foregroundColor(isSelected ? .editorTextPrimary : .editorTextSecondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(isSelected ? Color.editorControlActive : Color.clear)
                        .cornerRadius(EditorType.Radius.button)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(help(option))
            }
        }
        .padding(1)
        .background(Color.editorControlFill)
        .cornerRadius(EditorType.Radius.field)
    }
}
