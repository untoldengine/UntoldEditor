//
//  DockResizePreviewLine.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The line drawn where a divider will land while it drags, over the whole
/// container, in the accent colour.
struct DockResizePreviewLine: View {
    let rect: CGRect?

    var body: some View {
        GeometryReader { _ in
            if let rect {
                Rectangle()
                    .fill(Color.editorAccent)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
