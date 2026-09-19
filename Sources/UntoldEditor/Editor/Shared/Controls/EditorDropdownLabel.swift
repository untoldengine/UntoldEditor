//
//  EditorDropdownLabel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The face of a dropdown: an optional leading view (an icon, a mode dot, a
/// shading swatch), the title and a small chevron, on the control fill with
/// radius 6. Use it as the label of a `Menu`, or of the button that opens an
/// `EditorPopupMenu`.
struct EditorDropdownLabel<Leading: View>: View {
    private let title: String
    private let minWidth: CGFloat?
    private let leading: Leading

    init(_ title: String, minWidth: CGFloat? = nil, @ViewBuilder leading: () -> Leading) {
        self.title = title
        self.minWidth = minWidth
        self.leading = leading()
    }

    var body: some View {
        HStack(spacing: 6) {
            leading
            Text(title)
                .font(EditorType.body)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.editorTextSecondary)
        }
        .padding(.horizontal, 8)
        .frame(minWidth: minWidth, minHeight: 24)
        .background(Color.editorControlFill)
        .cornerRadius(EditorType.Radius.field)
        .contentShape(Rectangle())
    }
}

extension EditorDropdownLabel where Leading == EmptyView {
    /// A dropdown face with a title and chevron only.
    init(_ title: String, minWidth: CGFloat? = nil) {
        self.init(title, minWidth: minWidth) {
            EmptyView()
        }
    }
}
