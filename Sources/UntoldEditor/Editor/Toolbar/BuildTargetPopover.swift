//
//  BuildTargetPopover.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The list behind the toolbar's build target button: one row per platform,
/// the current one checked.
struct BuildTargetPopover: View {
    @Binding var target: EditorBuildTarget
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(EditorBuildTarget.allCases) { candidate in
                EditorPopupMenuRow(title: candidate.title, isChecked: candidate == target) {
                    target = candidate
                    onDone()
                }
            }
        }
        .padding(6)
        .frame(width: 180)
        .background(Color.editorPanelBackground)
    }
}
