//
//  VisionProPreviewContent.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
#if canImport(CompositorServices)
    @_weakLinked import CompositorServices
    import SwiftUI
    import UntoldEngine

    /// What the space draws: the editor's renderer through a compositor
    /// layer, for the headset the system chose.
    @available(macOS 26.0, *)
    struct VisionProPreviewContent: CompositorContent {
        @Environment(\.remoteDeviceIdentifier) private var remoteDevice

        var body: some CompositorContent {
            CompositorLayer(configuration: VisionProLayerConfiguration()) { @MainActor layerRenderer in
                guard let remoteDevice else {
                    Logger.log(message: "Vision Pro preview: the space opened without a headset.")
                    return
                }
                VisionProPreviewSession.shared.spaceDidOpen(
                    frames: CompositorFrameSource(layerRenderer: layerRenderer, device: remoteDevice)
                )
            }
        }
    }

    /// The layer as the engine draws it: one texture per eye, the viewport's
    /// formats, no foveation.
    @available(macOS 26.0, *)
    struct VisionProLayerConfiguration: CompositorLayerConfiguration {
        func makeConfiguration(capabilities: LayerRenderer.Capabilities, configuration: inout LayerRenderer.Configuration) {
            configuration.layout = .dedicated
            configuration.isFoveationEnabled = false
            if capabilities.supportedColorFormats(options: []).contains(.bgra8Unorm_srgb) {
                configuration.colorFormat = .bgra8Unorm_srgb
            }
            if capabilities.supportedDepthFormats.contains(.depth32Float) {
                configuration.depthFormat = .depth32Float
            }
        }
    }
#endif
