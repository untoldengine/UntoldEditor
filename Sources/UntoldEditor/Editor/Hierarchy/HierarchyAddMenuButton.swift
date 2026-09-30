//
//  HierarchyAddMenuButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The `+` beside the hierarchy's filter field: the add-entity menu.
struct HierarchyAddMenuButton: View {
    let actions: AddEntityActions

    var body: some View {
        Menu {
            addEntityMenuItems(actions)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.editorTextPrimary)
                .frame(width: 26, height: 26)
                .background(Color.editorControlFill)
                .cornerRadius(EditorType.Radius.field)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add to scene")
    }
}
