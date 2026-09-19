//
//  GaussianStreamingSettingsInspector.swift
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

struct GaussianStreamingSettingsInspector: View {
    let entityId: EntityID
    let settings: EditorGaussianStreamingSettings
    let refreshView: () -> Void

    @State private var streamingRadius = ""
    @State private var unloadRadius = ""
    @State private var priority = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GaussianStreamingNumberRow(
                label: "Load Radius",
                value: $streamingRadius,
                onCommit: commit
            )
            GaussianStreamingNumberRow(
                label: "Unload Radius",
                value: $unloadRadius,
                onCommit: commit
            )
            GaussianStreamingNumberRow(
                label: "Priority",
                value: $priority,
                onCommit: commit
            )
        }
        .onAppear(perform: sync)
        .onChange(of: settings) { _, _ in sync() }
    }

    private func sync() {
        streamingRadius = String(format: "%.2f", settings.streamingRadius)
        unloadRadius = String(format: "%.2f", settings.unloadRadius)
        priority = "\(settings.priority)"
    }

    private func commit() {
        guard let load = Float(streamingRadius),
              let unload = Float(unloadRadius),
              let priorityValue = Int(priority)
        else {
            sync()
            return
        }

        let normalized = editorNormalizedGaussianStreamingSettings(
            EditorGaussianStreamingSettings(
                streamingRadius: load,
                unloadRadius: unload,
                priority: priorityValue
            )
        )
        if updateEditorGaussianStreamingSettings(entityId: entityId, settings: normalized) {
            refreshView()
        }
    }
}
