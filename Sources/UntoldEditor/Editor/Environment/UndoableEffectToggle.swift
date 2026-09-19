//
//  UndoableEffectToggle.swift
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

struct UndoableEffectToggle<Label: View>: View {
    let undoName: String
    @Binding var isOn: Bool
    @ViewBuilder let label: () -> Label

    var body: some View {
        HStack {
            label()
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { newValue in
                    let oldValue = isOn
                    isOn = newValue
                    DispatchQueue.main.async {
                        EditorUndoManager.shared.registerValueChange(
                            name: undoName,
                            oldValue: oldValue,
                            newValue: newValue,
                            apply: { isOn = $0 }
                        )
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Color.editorAccent)
        }
    }
}
