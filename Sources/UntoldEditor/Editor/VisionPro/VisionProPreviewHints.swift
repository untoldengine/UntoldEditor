//
//  VisionProPreviewHints.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// How to move while the headset shows the scene, under the label over the
/// viewport: the keys, the trackpad, and the way out. Large enough to read
/// through the headset.
struct VisionProPreviewHints: View {
    struct Line: Identifiable {
        let keys: String
        let does: String

        var id: String {
            keys
        }
    }

    static let lines = [
        Line(keys: "Move the mouse, or a finger", does: "Turn the view, as your head does"),
        Line(keys: "W A S D", does: "Move along the floor, where you face"),
        Line(keys: "Q E", does: "Up and down"),
        Line(keys: "Esc", does: "End the preview"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Self.lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(line.keys)
                        .font(EditorType.badge)
                        .foregroundColor(.editorTextPrimary)
                        .frame(width: 200, alignment: .trailing)
                    Text(line.does)
                        .font(EditorType.hint)
                        .foregroundColor(.editorTextTertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.editorScrim)
        .overlay(
            RoundedRectangle(cornerRadius: EditorType.Radius.card)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(EditorType.Radius.card)
    }
}
