//
//  TileMeshListInspectorView.swift
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

struct TileMeshListInspectorView: View {
    let entityId: EntityID

    private var tileComponent: TileComponent? {
        scene.get(component: TileComponent.self, for: entityId)
    }

    private var meshEntries: [TileMeshInspectorEntry] {
        getEntityChildren(parentId: entityId)
            .flatMap { childId -> [TileMeshInspectorEntry] in
                guard let renderComponent = scene.get(component: RenderComponent.self, for: childId) else {
                    return []
                }

                return renderComponent.mesh.enumerated().map { meshIndex, mesh in
                    TileMeshInspectorEntry(
                        entityId: childId,
                        meshIndex: meshIndex,
                        name: mesh.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        submeshCount: mesh.submeshes.count
                    )
                }
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Tile Meshes", systemImage: "square.stack.3d.up")
                    .font(.headline)
                Spacer()
                Text("\(meshEntries.count)")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            }

            if let tileComponent {
                VStack(alignment: .leading, spacing: 4) {
                    tileInfoRow("Tile", tileComponent.tileId.isEmpty ? getEntityName(entityId: entityId) : tileComponent.tileId)
                    tileInfoRow("State", String(describing: tileComponent.state))
                    tileInfoRow("Visual", String(describing: tileComponent.visualState))
                }
                .font(.caption)
            }

            if meshEntries.isEmpty {
                Text("No resident meshes for this tile yet.")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(meshEntries) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: "cube.fill")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)

                            Text(entry.displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text("\(entry.submeshCount) sub")
                                .font(.caption2)
                                .foregroundColor(.editorTextSecondary)
                        }
                    }
                }
            }
        }
        .padding(8)
        .background(Color.editorFill)
        .cornerRadius(8)
    }

    private func tileInfoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.editorTextSecondary)
            Spacer()
            Text(value)
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
