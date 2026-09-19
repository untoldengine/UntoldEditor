//
//  RangeSlider.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import simd
import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// A slider that reports only when the drag ends, so one drag is one undo step.
struct RangeSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float?
    @State private var dragValue: Float?

    var body: some View {
        let shown = Binding<Float>(
            get: { min(max(dragValue ?? value, range.lowerBound), range.upperBound) },
            set: { dragValue = $0 }
        )
        let editingChanged: (Bool) -> Void = { isEditing in
            if isEditing == false, let final = dragValue {
                value = final
                dragValue = nil
            }
        }
        Group {
            if let step, step > 0 {
                Slider(value: shown, in: range, step: step, onEditingChanged: editingChanged)
            } else {
                Slider(value: shown, in: range, onEditingChanged: editingChanged)
            }
        }
        .controlSize(.mini)
    }
}
