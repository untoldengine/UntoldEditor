//
//  ToneMappingEditorView.swift
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

struct ToneMappingEditorView: View {
    @State private var selectedOperator = EditorTonemapOption.currentEngineOperator()

    private func refreshFromEngine() {
        selectedOperator = EditorTonemapOption.currentEngineOperator()
    }

    private func selectOperator(_ newValue: EditorTonemapOption) {
        let oldValue = selectedOperator
        guard oldValue != newValue else { return }

        let before = EditorPostFXSnapshot()
        selectedOperator = newValue
        setPostFX(.tonemapOperator(newValue.engineOperator))
        EditorUndoManager.shared.registerPostFXChange(
            name: "Change Tonemap Operator",
            before: before,
            after: EditorPostFXSnapshot()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Operator", selection: Binding(
                get: { selectedOperator },
                set: selectOperator
            )) {
                ForEach(EditorTonemapOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .onAppear(perform: refreshFromEngine)
        .onReceive(NotificationCenter.default.publisher(for: .editorPostFXStateDidChange)) { _ in
            refreshFromEngine()
        }
    }
}
