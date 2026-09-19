//
//  EditorPopupMenuRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A row of an `EditorPopupMenu`: a checkmark slot, the title, an optional
/// subtitle under it and a right-aligned monospaced shortcut. The checked row
/// takes the accent fill with inverse text.
struct EditorPopupMenuRow: View {
    let title: String
    var subtitle: String?
    var shortcut: String?
    var isChecked = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(isChecked ? Color.editorTextInverse : Color.clear)
                    .frame(width: 12)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(EditorType.title)
                        .foregroundColor(Self.textColor(isChecked: isChecked))
                    if let subtitle {
                        Text(subtitle)
                            .font(EditorType.hint)
                            .foregroundColor(Self.detailColor(isChecked: isChecked))
                    }
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(EditorType.mono)
                        .foregroundColor(Self.detailColor(isChecked: isChecked))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isChecked ? Color.editorAccent : Color.clear)
            .cornerRadius(EditorType.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    /// Title color: inverse on the accent fill, primary otherwise.
    static func textColor(isChecked: Bool) -> Color {
        isChecked ? .editorTextInverse : .editorTextPrimary
    }

    /// Subtitle and shortcut color: inverse on the accent fill, tertiary otherwise.
    static func detailColor(isChecked: Bool) -> Color {
        isChecked ? Color.editorTextInverse.opacity(0.8) : .editorTextTertiary
    }
}
