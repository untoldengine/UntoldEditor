//
//  EditorSlider.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A 4 pt slider: the track in the subtle fill, the part up to the value in
/// the accent, a round thumb. A drag anywhere on it sets the value.
struct EditorSlider: View {
    @Binding var value: Float
    var range: ClosedRange<Float> = 0 ... 1
    var isEnabled = true

    private let thumbSize: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fraction = CGFloat(Self.fraction(of: value, in: range))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.editorFill)
                    .frame(height: 4)
                Capsule()
                    .fill(Color.editorAccent)
                    .frame(width: max(0, fraction * width), height: 4)
                Circle()
                    .fill(Color.editorTextPrimary)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: max(0, min(width - thumbSize, fraction * width - thumbSize / 2)))
            }
            .frame(width: width, height: 16)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        value = Self.value(atX: drag.location.x, width: width, in: range)
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.5)
    }

    /// Where a value sits on the track, 0 to 1.
    static func fraction(of value: Float, in range: ClosedRange<Float>) -> Float {
        guard range.upperBound > range.lowerBound else {
            return 0
        }
        return max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    /// The value for a point along a track of `width`.
    static func value(atX x: CGFloat, width: CGFloat, in range: ClosedRange<Float>) -> Float {
        guard width > 0 else {
            return range.lowerBound
        }
        let fraction = Float(max(0, min(1, x / width)))
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}
