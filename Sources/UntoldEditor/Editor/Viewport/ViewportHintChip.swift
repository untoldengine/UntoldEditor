//
//  ViewportHintChip.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One hint at the bottom of the viewport: what is done, then how.
struct ViewportHintChip: View {
    let hint: ViewportHint

    var body: some View {
        HStack(spacing: 5) {
            Text(hint.action)
                .foregroundColor(.editorTextSecondary)
            Text(hint.keys)
                .foregroundColor(.editorTextPrimary)
        }
        .font(EditorType.hint)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Color.editorScrim)
        .cornerRadius(EditorType.Radius.button)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hint.action): \(hint.keys)")
    }
}
