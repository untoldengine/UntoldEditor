//
//  InspectorSectionView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// One component of the Inspector: a 30 pt header with the chevron, the title,
/// the enable dot where the component has one, a Reset link where it can be
/// reset, and the ⋯ menu with Reset, Copy, Paste and Remove; then the
/// component's editor, and a hairline.
struct InspectorSectionView<Content: View>: View {
    let title: String
    /// The component's enable flag; nil shows no dot.
    var isEnabled: Bool?
    var onReset: (() -> Void)?
    var onCopy: (() -> Void)?
    var onPaste: (() -> Void)?
    /// Paste is greyed until something of this kind was copied.
    var canPaste = false
    var onRemove: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.editorTextSecondary)
                            .frame(width: 8)
                        Text(title)
                            .font(EditorType.title)
                            .foregroundColor(.editorTextPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)

                if let isEnabled {
                    Circle()
                        .fill(isEnabled ? Color.editorSuccess : Color.editorTextDisabled)
                        .frame(width: 7, height: 7)
                        .help(isEnabled ? "Enabled" : "Disabled")
                }
                if let onReset {
                    Button("Reset", action: onReset)
                        .buttonStyle(.plain)
                        .font(EditorType.hint)
                        .foregroundColor(.editorTextSecondary)
                        .focusable(false)
                        .help("Back to the defaults")
                }
                if hasMenu {
                    Menu {
                        menuItems
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.editorTextSecondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Section actions")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)

            if isExpanded {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }

            Color.editorHairline.frame(height: 1)
        }
    }

    private var hasMenu: Bool {
        onReset != nil || onCopy != nil || onPaste != nil || onRemove != nil
    }

    @ViewBuilder private var menuItems: some View {
        if let onReset {
            Button("Reset", action: onReset)
        }
        if let onCopy {
            Button("Copy", action: onCopy)
        }
        if let onPaste {
            Button("Paste", action: onPaste)
                .disabled(canPaste == false)
        }
        if onRemove != nil, onReset != nil || onCopy != nil {
            Divider()
        }
        if let onRemove {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}
