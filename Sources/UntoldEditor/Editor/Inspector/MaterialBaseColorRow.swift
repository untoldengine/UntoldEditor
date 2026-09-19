//
//  MaterialBaseColorRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The base colour of the material: a swatch, its hex, and the colour well.
struct MaterialBaseColorRow: View {
    let entityId: EntityID
    let meshIndex: Int
    var isEnabled = true
    let onChanged: () -> Void

    var body: some View {
        let color = getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)
        HStack(spacing: 8) {
            Text("Base color")
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 64, alignment: .leading)
            RoundedRectangle(cornerRadius: 3)
                .fill(colorFromSimd(color))
                .frame(width: 14, height: 14)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.editorHairline, lineWidth: 1))
            Text(MaterialSnapshot.hex(color))
                .font(EditorType.mono)
                .foregroundColor(.editorTextPrimary)
            Spacer()
            ColorPicker("", selection: Binding(
                get: { colorFromSimd(color) },
                set: { newColor in
                    updateMaterialColor(entityId: entityId, color: newColor, meshIndex: meshIndex)
                    EditorSceneDirtyState.shared.markDirty()
                    onChanged()
                }
            ))
            .labelsHidden()
            .disabled(isEnabled == false)
            .opacity(isEnabled ? 1 : 0.7)
        }
    }
}
