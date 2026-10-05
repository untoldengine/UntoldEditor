//
//  MarqueeView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The dashed rectangle dragged over the viewport, which selects what is
/// inside it when the button is released. It takes no click itself.
struct MarqueeView: View {
    /// The rectangle in points from the top left of the viewport.
    let rect: CGRect

    static let lineWidth: CGFloat = 1.5
    static let cornerRadius: CGFloat = 3

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(Self.cornerRadius, min(rect.width, rect.height) / 2))
        shape
            .fill(Color.editorAccent.opacity(0.10))
            .overlay {
                shape.stroke(Color.editorAccent, style: StrokeStyle(lineWidth: Self.lineWidth, dash: [6, 4]))
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
