//
//  EditorFilterChip.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A filter chip, as in the console sub-bar: an optional glyph in its own tint,
/// a label such as "2 errors", 22 pt, raised on the active surface when it is the
/// selected filter.
struct EditorFilterChip: View {
    let label: String
    var systemImage: String?
    var tint: Color = .editorTextSecondary
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(tint)
                }
                Text(label)
                    .font(EditorType.hint)
                    .foregroundColor(Self.labelColor(isActive: isActive, tint: tint))
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(isActive ? Color.editorControlActive : Color.clear)
            .cornerRadius(EditorType.Radius.field)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    /// The label reads in primary text when the chip is the active filter and in
    /// its own tint otherwise.
    static func labelColor(isActive: Bool, tint: Color) -> Color {
        isActive ? .editorTextPrimary : tint
    }
}
