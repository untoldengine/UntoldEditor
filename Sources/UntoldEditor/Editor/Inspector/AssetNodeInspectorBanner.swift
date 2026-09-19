//
//  AssetNodeInspectorBanner.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

struct AssetNodeInspectorBanner: View {
    let entityId: EntityID
    @ObservedObject var selectionManager: SelectionManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isBindableAssetMeshNode(entityId) ? "cube.fill" : "square.stack.3d.up")
                .foregroundColor(.editorTextSecondary)

            Text(isBindableAssetMeshNode(entityId) ? "Mesh Node" : "Asset Node")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)

            Spacer()

            if let rootId = assetRootEntityId(for: entityId), rootId != .invalid {
                Button(action: {
                    selectionManager.selectEntity(entityId: rootId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left")
                        Text(getEntityName(entityId: rootId))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Select asset root")
            }
        }
        .padding(6)
        .background(Color.editorFill)
        .cornerRadius(6)
    }
}
