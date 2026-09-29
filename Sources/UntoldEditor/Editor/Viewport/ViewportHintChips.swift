//
//  ViewportHintChips.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The shortcut hints along the bottom of the viewport. As many as fit in
/// its width show, the most useful first. Clicks go through them to the scene.
struct ViewportHintChips: View {
    let hints: [ViewportHint]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.lengths(for: hints.count), id: \.self) { length in
                row(of: Array(hints.prefix(length)))
            }
        }
        .allowsHitTesting(false)
    }

    private func row(of hints: [ViewportHint]) -> some View {
        HStack(spacing: 6) {
            ForEach(hints) { hint in
                ViewportHintChip(hint: hint)
            }
        }
    }

    /// How many hints each candidate row holds: all of them, then one fewer
    /// each time, down to the first alone.
    static func lengths(for count: Int) -> [Int] {
        count > 0 ? Array((1 ... count).reversed()) : []
    }
}
