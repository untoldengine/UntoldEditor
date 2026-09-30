//
//  MaterialAdvancedView.swift
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

/// The rest of the material, under the Material block's disclosure: the
/// texture slots, the UV scale, parallax (height scale, midlevel, POM, remap),
/// the alpha mask, the emissive colour, and the write-back to an `.untold`
/// asset while inspecting one.
struct MaterialAdvancedView: View {
    let entityId: EntityID
    let meshIndex: Int
    let asset: Asset?
    let inspectionOnly: Bool
    let refreshView: () -> Void
    /// Runs a material edit; the block notes it for the `.untold` write-back.
    let edit: (() -> Void) -> Void
    @Binding var hasPendingUntoldWrite: Bool
    @Binding var untoldUpdateStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(TextureType.allCases) { type in
                        MaterialTextureSlotView(entityId: entityId, meshIndex: meshIndex, type: type, asset: asset, inspectionOnly: inspectionOnly, refreshView: refreshView)
                    }
                }
                .padding(.horizontal, 4)
            }

            numberRow("UV Scale", value: Binding(
                get: { getMaterialSTScale(entityId: entityId, meshIndex: meshIndex) },
                set: { newValue in
                    updateMaterialSTScale(entityId: entityId, stScale: newValue, meshIndex: meshIndex)
                    EditorSceneDirtyState.shared.markDirty()
                    refreshView()
                }
            ))
            .disabled(inspectionOnly)
            .opacity(inspectionOnly ? 0.7 : 1.0)

            Text("Parallax")
                .font(EditorType.hint)
                .foregroundColor(.editorTextTertiary)

            // Height Scale: total Parallax Occlusion Mapping ray-march depth, in
            // UV-normalized units. Only has a visible effect once a Height texture
            // is assigned above.
            numberRow("Height Scale", value: Binding(
                get: { getMaterialHeightScale(entityId: entityId, meshIndex: meshIndex) },
                set: { newValue in edit { updateMaterialHeightScale(entityId: entityId, heightScale: newValue, meshIndex: meshIndex) } }
            ))
            // Midlevel matches Blender's Displacement node "Midlevel" (default 0.5 = no shift).
            numberRow("Midlevel", value: Binding(
                get: { getMaterialHeightMidlevel(entityId: entityId, meshIndex: meshIndex) },
                set: { newValue in edit { updateMaterialHeightMidlevel(entityId: entityId, heightMidlevel: newValue, meshIndex: meshIndex) } }
            ))
            // Height Remap Min/Max contrast-stretch the raw height sample before
            // Midlevel is applied; many displacement maps only use a narrow slice of
            // [0,1]. Identity is (0.0, 1.0).
            numberRow("Remap Min", value: Binding(
                get: { getMaterialHeightRemapMin(entityId: entityId, meshIndex: meshIndex) },
                set: { newValue in edit { updateMaterialHeightRemapMin(entityId: entityId, heightRemapMin: newValue, meshIndex: meshIndex) } }
            ))
            numberRow("Remap Max", value: Binding(
                get: { getMaterialHeightRemapMax(entityId: entityId, meshIndex: meshIndex) },
                set: { newValue in edit { updateMaterialHeightRemapMax(entityId: entityId, heightRemapMax: newValue, meshIndex: meshIndex) } }
            ))
            // POM on/off lets testers compare normal mapping alone against normal
            // mapping with parallax without discarding the height texture.
            HStack {
                Text("POM")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextSecondary)
                    .frame(width: 64, alignment: .leading)
                Toggle("", isOn: Binding(
                    get: { getMaterialHeightEnabled(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialHeightEnabled(entityId: entityId, heightEnabled: newValue, meshIndex: meshIndex) } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.editorAccent)
                .controlSize(.small)
                Spacer()
            }

            HStack {
                Text("Alpha mask")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextSecondary)
                    .frame(width: 64, alignment: .leading)
                Picker("", selection: Binding(
                    get: { getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialAlphaMode(entityId: entityId, mode: newValue, meshIndex: meshIndex) } }
                )) {
                    ForEach(MaterialAlphaMode.allCases) { mode in
                        Text(mode.description).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .labelsHidden()
                .frame(width: 140)
                Spacer()
            }

            if inspectionOnly, isUntoldBackedMesh, hasPendingUntoldWrite {
                Button(action: updateUntoldAsset) {
                    Text("Update .untold")
                }
                .buttonStyle(.borderedProminent)

                if let untoldUpdateStatus {
                    Text(untoldUpdateStatus)
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Emissive colour")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextSecondary)
                TextInputVectorView(
                    label: "",
                    value: Binding(
                        get: { getMaterialEmmissive(entityId: entityId, meshIndex: meshIndex) },
                        set: { newValue in
                            updateMaterialEmmisive(entityId: entityId, emmissive: newValue, meshIndex: meshIndex)
                            EditorSceneDirtyState.shared.markDirty()
                            refreshView()
                        }
                    )
                )
                .frame(width: 200)
            }
            .disabled(inspectionOnly)
            .opacity(inspectionOnly ? 0.7 : 1.0)
        }
    }

    private func numberRow(_ label: String, value: Binding<Float>) -> some View {
        HStack {
            Text(label)
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 64, alignment: .leading)
            TextInputNumberView(label: "", value: value)
                .frame(width: 70)
            Spacer()
        }
    }

    private var isUntoldBackedMesh: Bool {
        resolveUntoldAssetURL(entityId: entityId) != nil
    }

    private func updateUntoldAsset() {
        do {
            try persistAlphaMaterialOverridesToUntold(
                entityId: entityId,
                meshIndex: meshIndex,
                opacity: getMaterialOpacity(entityId: entityId, meshIndex: meshIndex),
                alphaCutoff: getMaterialAlphaCutoff(entityId: entityId, meshIndex: meshIndex),
                roughness: getMaterialRoughness(entityId: entityId, meshIndex: meshIndex),
                metallic: getMaterialMetallic(entityId: entityId, meshIndex: meshIndex),
                alphaMode: getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex)
            )
            hasPendingUntoldWrite = false
            untoldUpdateStatus = "Updated \(resolveUntoldAssetURL(entityId: entityId)?.lastPathComponent ?? ".untold")"
            refreshView()
        } catch {
            untoldUpdateStatus = error.localizedDescription
        }
    }
}
