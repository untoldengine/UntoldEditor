//
//  MaterialSectionView.swift
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

/// The Material block of the Mesh Renderer: the lit sphere, the Metallic,
/// Roughness, Emission and Opacity sliders, the base colour, and the rest of
/// the material under a disclosure. While inspecting a mesh backed by an
/// `.untold` asset, edits to the values the asset stores can be written back.
struct MaterialSectionView: View {
    let entityId: EntityID
    let meshIndex: Int
    let asset: Asset?
    let inspectionOnly: Bool
    let refreshView: () -> Void

    @State private var hasPendingUntoldWrite = false
    @State private var untoldUpdateStatus: String?
    @State private var showsMore = false

    var body: some View {
        let baseColor = getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)
        let roughness = getMaterialRoughness(entityId: entityId, meshIndex: meshIndex)
        let metallic = getMaterialMetallic(entityId: entityId, meshIndex: meshIndex)
        let emissive = getMaterialEmmissive(entityId: entityId, meshIndex: meshIndex)
        let opacity = getMaterialOpacity(entityId: entityId, meshIndex: meshIndex)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Material")
                    .font(EditorType.title)
                    .foregroundColor(.editorTextPrimary)
                Text(editorMeshLabel(entityId: entityId, meshIndex: meshIndex, inspectionOnly: inspectionOnly))
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                MaterialSphereView(
                    baseColor: colorFromSimd(baseColor),
                    roughness: roughness,
                    metallic: metallic,
                    emission: MaterialSnapshot.emissionStrength(of: emissive),
                    opacity: opacity
                )
                VStack(spacing: 6) {
                    MaterialSliderRow(label: "Metallic", value: Binding(
                        get: { metallic },
                        set: { newValue in edit { updateMaterialMetallic(entityId: entityId, metallic: newValue, meshIndex: meshIndex) } }
                    ))
                    MaterialSliderRow(label: "Roughness", value: Binding(
                        get: { roughness },
                        set: { newValue in edit { updateMaterialRoughness(entityId: entityId, roughness: newValue, meshIndex: meshIndex) } }
                    ))
                    MaterialSliderRow(label: "Emission", value: Binding(
                        get: { MaterialSnapshot.emissionStrength(of: emissive) },
                        set: { strength in
                            edit {
                                updateMaterialEmmisive(
                                    entityId: entityId,
                                    emmissive: MaterialSnapshot.emissive(forStrength: strength, current: emissive, baseColor: baseColor),
                                    meshIndex: meshIndex
                                )
                            }
                        }
                    ), isEnabled: inspectionOnly == false)
                    MaterialSliderRow(label: "Opacity", value: Binding(
                        get: { opacity },
                        set: { newValue in edit { updateMaterialOpacity(entityId: entityId, opacity: newValue, meshIndex: meshIndex, submeshIndex: 0) } }
                    ))
                }
            }

            MaterialBaseColorRow(entityId: entityId, meshIndex: meshIndex, isEnabled: inspectionOnly == false, onChanged: refreshView)

            DisclosureGroup(isExpanded: $showsMore) {
                MaterialAdvancedView(
                    entityId: entityId,
                    meshIndex: meshIndex,
                    asset: asset,
                    inspectionOnly: inspectionOnly,
                    refreshView: refreshView,
                    edit: edit,
                    hasPendingUntoldWrite: $hasPendingUntoldWrite,
                    untoldUpdateStatus: $untoldUpdateStatus
                )
                .padding(.top, 6)
            } label: {
                Text("Textures, parallax and alpha")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextSecondary)
            }
            .disclosureGroupStyle(EditorDisclosureStyle())
        }
        .onAppear(perform: forgetPendingWrite)
        .onChange(of: entityId) { _, _ in forgetPendingWrite() }
        .onChange(of: meshIndex) { _, _ in forgetPendingWrite() }
    }

    /// Runs a material edit. While inspecting a mesh backed by an `.untold`
    /// asset, the edit can be written to the asset, so the button appears.
    private func edit(_ change: () -> Void) {
        change()
        EditorSceneDirtyState.shared.markDirty()
        if inspectionOnly, resolveUntoldAssetURL(entityId: entityId) != nil {
            hasPendingUntoldWrite = true
            untoldUpdateStatus = nil
        }
        refreshView()
    }

    private func forgetPendingWrite() {
        hasPendingUntoldWrite = false
        untoldUpdateStatus = nil
    }
}
