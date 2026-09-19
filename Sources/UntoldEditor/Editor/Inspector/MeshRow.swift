//
//  MeshRow.swift
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

/// The Mesh row of the Mesh Renderer: the material's colour, the mesh's name,
/// and the button that assigns the model selected in Assets.
struct MeshRow: View {
    let entityId: EntityID
    let meshIndex: Int
    let label: String
    /// False while the mesh is not editable: composition-only mode, or inspecting an asset's node.
    let canAssign: Bool
    /// The model selected in the Asset Browser, which the button assigns.
    let selectedModel: URL?
    let onAssign: (URL) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Mesh")
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 64, alignment: .leading)
            RoundedRectangle(cornerRadius: 3)
                .fill(colorFromSimd(getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)))
                .frame(width: 12, height: 12)
            Text(label)
                .font(EditorType.body)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if canAssign {
                EditorIconButton(
                    systemImage: "circle.circle",
                    size: 22,
                    help: selectedModel == nil ? "Select a model in Assets to assign it here" : "Assign the model selected in Assets"
                ) {
                    if let selectedModel {
                        onAssign(selectedModel)
                    }
                }
                .disabled(selectedModel == nil)
            }
        }
    }
}
