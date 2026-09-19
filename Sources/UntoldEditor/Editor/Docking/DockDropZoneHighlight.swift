//
//  DockDropZoneHighlight.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Where a dragged tab would land, drawn over the target while the drag hovers
/// it: a whole area, or the strip of the viewport that stands for one.
struct DockDropZoneHighlight: View {
    let rect: CGRect?

    var body: some View {
        GeometryReader { _ in
            if let rect {
                RoundedRectangle(cornerRadius: EditorType.Radius.field)
                    .fill(Color.editorAccentSoft)
                    .overlay(
                        RoundedRectangle(cornerRadius: EditorType.Radius.field)
                            .stroke(Color.editorAccent, lineWidth: 1.5)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
