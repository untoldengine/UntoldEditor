//
//  ColorGradeLUTEditorView.swift
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

struct ColorGradeLUTEditorView: View {
    @Binding var selectedAsset: Asset?
    @State private var enableColorGradeLUT = ColorGradeLUTParams.shared.enabled
    @State private var appliedLUTName: String?

    private var appliedLUTDisplayName: String {
        appliedLUTName ?? (enableColorGradeLUT ? "Scene Authored" : "None")
    }

    private var selectedLUTAsset: Asset? {
        guard let selectedAsset,
              selectedAsset.category == AssetCategory.lut.rawValue,
              selectedAsset.isFolder == false,
              selectedAsset.path.pathExtension.lowercased() == "cube"
        else {
            return nil
        }

        return selectedAsset
    }

    private func refreshFromEngine() {
        enableColorGradeLUT = ColorGradeLUTParams.shared.enabled

        if let source = ColorGradeLUTParams.shared.source {
            appliedLUTName = URL(fileURLWithPath: source.filename).lastPathComponent
        } else if let editorColorGradeLUTPath {
            appliedLUTName = URL(fileURLWithPath: editorColorGradeLUTPath).lastPathComponent
        } else {
            appliedLUTName = nil
        }
    }

    private func applySelectedLUT() {
        guard let lut = selectedLUTAsset else {
            return
        }

        let before = EditorPostFXSnapshot()
        setColorGradeLUT(filename: lut.path.path)
        enableColorGradeLUT = ColorGradeLUTParams.shared.enabled
        editorColorGradeLUTPath = ColorGradeLUTParams.shared.enabled ? lut.path.path : nil
        appliedLUTName = ColorGradeLUTParams.shared.enabled ? lut.name : nil
        EditorUndoManager.shared.registerPostFXChange(
            name: "Apply Color Grade LUT",
            before: before,
            after: EditorPostFXSnapshot()
        )
    }

    private func setLUTEnabled(_ isEnabled: Bool) {
        let before = EditorPostFXSnapshot()

        if isEnabled, ColorGradeLUTParams.shared.enabled == false, selectedLUTAsset != nil {
            applySelectedLUT()
            return
        }

        setPostFX(.colorGradeLUT(.enabled(isEnabled)))
        enableColorGradeLUT = ColorGradeLUTParams.shared.enabled
        if enableColorGradeLUT == false {
            editorColorGradeLUTPath = nil
            appliedLUTName = nil
        }
        EditorUndoManager.shared.registerPostFXChange(
            name: isEnabled ? "Enable Color Grade LUT" : "Disable Color Grade LUT",
            before: before,
            after: EditorPostFXSnapshot()
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Enable LUT", systemImage: enableColorGradeLUT ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(
                    get: { enableColorGradeLUT },
                    set: setLUTEnabled
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Color.editorAccent)
            }

            Button(action: applySelectedLUT) {
                HStack(spacing: 6) {
                    Image(systemName: "camera.filters")
                        .font(.system(size: 12))
                    Text("Apply Selected LUT")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selectedLUTAsset == nil ? Color.editorSurface.opacity(0.45) : Color.editorSurface)
                .foregroundColor(selectedLUTAsset == nil ? .editorTextTertiary : .editorTextPrimary)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(selectedLUTAsset == nil)
            .help("Select a .cube file in the Asset Browser's LUT folder, then apply it here.")

            HStack {
                Text("Selected")
                    .foregroundColor(.editorTextSecondary)
                Spacer()
                Text(selectedLUTAsset?.name ?? "None")
                    .foregroundColor(.editorTextTertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 11))

            HStack {
                Text("Applied")
                    .foregroundColor(.editorTextSecondary)
                Spacer()
                Text(appliedLUTDisplayName)
                    .foregroundColor(.editorTextTertiary)
                    .lineLimit(1)
            }
            .font(.system(size: 11))
        }
        .padding(.vertical, 4)
        .onAppear(perform: refreshFromEngine)
        .onReceive(NotificationCenter.default.publisher(for: .editorPostFXStateDidChange)) { _ in
            refreshFromEngine()
        }
    }
}
