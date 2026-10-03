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
/// many are selected. From Play to Stop it says why a click selects nothing.
struct HierarchyFooterView: View {
    let entityCount: Int
    let selectedCount: Int
    var isPlaying = false

    var body: some View {
        HStack {
            Text(Self.summary(entityCount: entityCount, selectedCount: selectedCount, isPlaying: isPlaying))
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

    /// "5 entities · 1 selected", with the status bar's entity wording; while
    /// the game plays, "5 entities · no selecting while playing".
    static func summary(entityCount: Int, selectedCount: Int, isPlaying: Bool = false) -> String {
        if isPlaying {
            return "\(EditorStatusModel.entities(entityCount)) · no selecting while playing"
        }
        return "\(EditorStatusModel.entities(entityCount)) · \(selectedCount) selected"
    }
}
