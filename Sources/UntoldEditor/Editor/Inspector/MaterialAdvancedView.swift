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
/// texture slots, the UV scale, the alpha mask, the emissive colour, the
/// write-back to an `.untold` asset while inspecting one, and the Height
/// detail (Parallax Occlusion Mapping) group at the end.
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

    @State private var showsHeightDetail = false

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

            heightDetailSection
        }
    }

    /// The Height-map-driven surface depth (Parallax Occlusion Mapping) group:
    /// set apart in its own collapsible, bordered block since it's an advanced,
    /// opt-in effect most materials never touch, rather than another loose row
    /// in the general list above.
    private var heightDetailSection: some View {
        let hasHeightTexture = getMaterialTextureURL(entityId: entityId, type: .height, meshIndex: meshIndex) != nil

        return DisclosureGroup(isExpanded: $showsHeightDetail) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Enable depth")
                        .font(EditorType.hint)
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: 80, alignment: .leading)
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
                .help("Makes the surface look like it has real depth, carved in by the Height map. Off by default — the Height map still affects shading for bump detail either way.")

                MaterialSliderRow(label: "Depth", value: Binding(
                    get: { getMaterialHeightScale(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialHeightScale(entityId: entityId, heightScale: newValue, meshIndex: meshIndex) } }
                ), range: 0 ... 0.2, labelWidth: 80)
                    .help("How far the surface appears to push inward. Start small — 0.02 to 0.05 is typical; higher values dig deeper but can distort at grazing angles.")

                MaterialSliderRow(label: "Flat level", value: Binding(
                    get: { getMaterialHeightMidlevel(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialHeightMidlevel(entityId: entityId, heightMidlevel: newValue, meshIndex: meshIndex) } }
                ), labelWidth: 80)
                    .help("The grey level of the Height map that sits flush with the surface — everything lighter pushes out, everything darker pushes in. Default 0.5 matches Blender's Displacement node.")

                MaterialSliderRow(label: "Black point", value: Binding(
                    get: { getMaterialHeightRemapMin(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialHeightRemapMin(entityId: entityId, heightRemapMin: newValue, meshIndex: meshIndex) } }
                ), labelWidth: 80)
                    .help("Like the black point in a Levels tool: raise it if the Height map only uses a narrow, washed-out range of greys and the depth effect looks too flat.")

                MaterialSliderRow(label: "White point", value: Binding(
                    get: { getMaterialHeightRemapMax(entityId: entityId, meshIndex: meshIndex) },
                    set: { newValue in edit { updateMaterialHeightRemapMax(entityId: entityId, heightRemapMax: newValue, meshIndex: meshIndex) } }
                ), labelWidth: 80)
                    .help("Like the white point in a Levels tool: lower it if the Height map only uses a narrow, washed-out range of greys and the depth effect looks too flat.")
            }
            .padding(.top, 2)
        } label: {
            HStack(spacing: 6) {
                Text("Height detail")
                    .font(EditorType.hint)
                    .foregroundColor(.editorTextTertiary)
                if !hasHeightTexture {
                    Text("(needs a Height map)")
                        .font(EditorType.hint)
                        .foregroundColor(.editorTextTertiary.opacity(0.6))
                }
            }
        }
        .disclosureGroupStyle(EditorDisclosureStyle())
        .padding(10)
        .background(Color.editorSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(6)
        .disabled(!hasHeightTexture)
        .opacity(hasHeightTexture ? 1.0 : 0.6)
    }

    private func numberRow(_ label: String, value: Binding<Float>, help: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(EditorType.hint)
                .foregroundColor(.editorTextSecondary)
                .frame(width: 64, alignment: .leading)
            TextInputNumberView(label: "", value: value)
                .frame(width: 70)
            Spacer()
        }
        .help(help ?? "")
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
