//
//  HierarchyFooterView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The line under the hierarchy tree: how many entities the scene has and how
/// many are selected.
struct HierarchyFooterView: View {
    let entityCount: Int
    let selectedCount: Int

    var body: some View {
        HStack {
            Text(Self.summary(entityCount: entityCount, selectedCount: selectedCount))
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .overlay(alignment: .top) {
            Color.editorHairline.frame(height: 1)
        }
    }

    /// "5 entities · 1 selected", with the status bar's entity wording.
    static func summary(entityCount: Int, selectedCount: Int) -> String {
        "\(EditorStatusModel.entities(entityCount)) · \(selectedCount) selected"
    }
}
