//
//  RenderingEditorView.swift
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
import UntoldEngine

private func onAddMesh_Editor(entityId: EntityID, url: URL) {
    let filename = url.deletingPathExtension().lastPathComponent
    let withExtension = url.pathExtension

    setEntityMeshAsync(entityId: entityId, filename: filename, withExtension: withExtension) { success in
        if success {
            print("✅ Mesh loaded: \(filename).\(withExtension)")
        } else {
            print("⚠️ Failed to load mesh, using fallback: \(filename).\(withExtension)")
        }
    }
}

/// The name shown for a mesh: the asset it came from, or the mesh's own name
/// while inspecting an asset's node.
func editorMeshLabel(entityId: EntityID, meshIndex: Int, inspectionOnly: Bool) -> String {
    guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
          renderComponent.mesh.indices.contains(meshIndex)
    else {
        return getAssetURLString(entityId: entityId) ?? " "
    }

    let mesh = renderComponent.mesh[meshIndex]
    let name = mesh.name.trimmingCharacters(in: .whitespacesAndNewlines)
    if inspectionOnly, !name.isEmpty {
        return name
    }

    return getAssetURLString(entityId: entityId) ?? (name.isEmpty ? " " : name)
}

/// The Mesh Renderer section: the mesh, Cast shadows, and the Material block.
struct RenderingEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void
    var meshIndex: Int = 0
    var inspectionOnly: Bool = false

    var body: some View {
        let readOnlyRender = EditorAuthoringMode.sceneCompositionOnly || inspectionOnly
        let hasRender = hasComponent(entityId: entityId, componentType: RenderComponent.self)

        return VStack(alignment: .leading, spacing: 10) {
            MeshRow(
                entityId: entityId,
                meshIndex: meshIndex,
                label: editorMeshLabel(entityId: entityId, meshIndex: meshIndex, inspectionOnly: inspectionOnly),
                canAssign: readOnlyRender == false,
                selectedModel: asset?.category == AssetCategory.models.rawValue ? asset?.path : nil,
                onAssign: { url in
                    onAddMesh_Editor(entityId: entityId, url: url)
                    refreshView()
                }
            )

            if hasRender {
                HStack {
                    Text("Cast shadows")
                        .font(EditorType.hint)
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: 64, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { getEntityCastsShadow(entityId: entityId) },
                        set: { enabled in
                            setEntityCastsShadow(entityId: entityId, enabled)
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(.editorAccent)
                    .controlSize(.small)
                    .disabled(inspectionOnly)
                    .opacity(inspectionOnly ? 0.7 : 1.0)
                    Spacer()
                }
            }

            if hasRender, hasComponent(entityId: entityId, componentType: LightComponent.self) == false {
                MaterialSectionView(
                    entityId: entityId,
                    meshIndex: meshIndex,
                    asset: asset,
                    inspectionOnly: inspectionOnly,
                    refreshView: refreshView
                )
            }
        }
    }
}
