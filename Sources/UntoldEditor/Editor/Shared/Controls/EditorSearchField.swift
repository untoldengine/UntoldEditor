//
//  EditorSearchField.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A search or filter field: a magnifier, the placeholder, and an optional
/// trailing hint such as a keyboard shortcut, on the control fill with radius 6.
/// The text field is the editor's `ExplicitClickTextField`, which takes focus
/// only on a click, so typing viewport shortcuts never lands in a filter.
struct EditorSearchField: View {
    @Binding var text: String
    let placeholder: String
    var hint: String?
    var width: CGFloat?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.editorTextTertiary)
            ExplicitClickTextField(text: $text, placeholder: placeholder)
            if let hint {
                Text(hint)
                    .font(EditorType.mono)
                    .foregroundColor(.editorTextDisabled)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: 26)
        .background(Color.editorControlFill)
        .cornerRadius(EditorType.Radius.field)
    }
}
