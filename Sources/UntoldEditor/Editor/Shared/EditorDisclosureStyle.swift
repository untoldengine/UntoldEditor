//
//  EditorDisclosureStyle.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Disclosure style where each nesting level is indented by exactly the width of
/// the expand/collapse chevron, so a child's content lines up with its parent's
/// label text. Also themes the chevron to match the editor.
struct EditorDisclosureStyle: DisclosureGroupStyle {
    private let chevronWidth: CGFloat = 12
    private let spacing: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: spacing) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: chevronWidth)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, chevronWidth + spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
