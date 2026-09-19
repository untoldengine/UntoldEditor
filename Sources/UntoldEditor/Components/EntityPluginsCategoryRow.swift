//
//  EntityPluginsCategoryRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// Fixed left-tree entry for the Entities shelf, next to Primitives and Lights. It holds the
/// kinds of entity that fit neither, and takes no room until loaded code adds one.
struct EntityPluginsCategoryRow: View {
    let isSelected: Bool
    let onSelect: () -> Void

    @ObservedObject private var library = ComponentLibraryController.shared

    var body: some View {
        if library.revision >= 0, EntityPluginShelfItem.items(on: .entities).isEmpty == false || isSelected {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.clear)
                    .frame(width: 10)

                Image(systemName: isSelected ? "square.stack.3d.up.fill" : "square.stack.3d.up")
                    .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
                Text(UntoldEntityShelf.entities.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.editorTextPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .padding(.leading, 12)
            .background(isSelected ? Color.editorAccentSoft : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
        }
    }
}
