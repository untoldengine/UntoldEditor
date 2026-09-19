//
//  GaussianLoadingModeInspector.swift
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

struct GaussianLoadingModeInspector: View {
    let entityId: EntityID
    let metadata: EditorGaussianAssetMetadata
    let refreshView: () -> Void

    private var canStream: Bool {
        GeometryStreamingSystem.shared.enabled && metadata.sourceURL.pathExtension.lowercased() == "untoldgs"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loading")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Picker("", selection: modeBinding) {
                ForEach(EditorGaussianLoadingMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .disabled(!canStream && metadata.loadingMode != .streaming)

            if metadata.loadingMode == .streaming {
                GaussianStreamingSettingsInspector(
                    entityId: entityId,
                    settings: metadata.streamingSettings,
                    refreshView: refreshView
                )
            }
        }
        .padding(8)
        .background(Color.editorFill)
        .cornerRadius(6)
    }

    private var modeBinding: Binding<EditorGaussianLoadingMode> {
        Binding(
            get: { metadata.loadingMode },
            set: { newMode in
                guard newMode != metadata.loadingMode else { return }
                guard newMode == .resident || canStream else { return }
                if updateEditorGaussianLoadingMode(entityId: entityId, loadingMode: newMode) {
                    refreshView()
                }
            }
        )
    }
}
