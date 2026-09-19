//
//  UndoableEffectSlider.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

struct UndoableEffectSlider: View {
    let label: String
    let undoName: String
    let range: ClosedRange<Float>
    var format: String = "%.2f"
    var help: String?
    let get: () -> Float
    let set: (Float) -> Void

    @State private var editStartValue: Float?

    var body: some View {
        Text(label)
        Slider(
            value: Binding(
                get: get,
                set: set
            ),
            in: range,
            onEditingChanged: { isEditing in
                if isEditing {
                    editStartValue = get()
                } else if let oldValue = editStartValue {
                    let newValue = get()
                    EditorUndoManager.shared.registerValueChange(
                        name: undoName,
                        oldValue: oldValue,
                        newValue: newValue,
                        apply: set
                    )
                    editStartValue = nil
                }
            }
        )
        .tint(Color.editorAccent)
        .help(help ?? "")
        Text(String(format: format, get()))
    }
}
