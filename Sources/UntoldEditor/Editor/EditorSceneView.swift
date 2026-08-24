//
//  EditorSceneView.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import MetalKit
import SwiftUI
import UntoldEngine

struct EditorSceneView: View, UntoldRendererDelegate {
    private var renderer: UntoldRenderer

    init(renderer: UntoldRenderer) {
        self.renderer = renderer
        self.renderer.delegate = self
    }

    var body: some View {
        SceneView(renderer: renderer)
            .onInit {
                let sceneCamera = createEntity()
                createSceneCamera(entityId: sceneCamera)

                CameraSystem.shared.activeCamera = sceneCamera

                // Load Debug meshes and other editor / debug resources
                loadLightDebugMeshes()
            }
    }

    /// UntoldRenderer delegate functions
    func willDraw(in _: MTKView) {
        if hotReload {
            // updateRayKernelPipeline()
            updateShadersAndPipeline()
            hotReload = false
        }
    }

    func didDraw(in _: MTKView) {
        // Detect the moment async asset/tile loading finishes and ask the Scene
        // Graph to refresh, so streamed-in entities appear without a manual action.
        SceneGraphLoadWatcher.shared.poll()
    }
}

/// Watches the engine's async-loading gate on the render loop and posts a
/// refresh notification on the falling edge (loading → idle).
final class SceneGraphLoadWatcher {
    static let shared = SceneGraphLoadWatcher()
    private var wasLoading = false
    private init() {}

    func poll() {
        let loading = AssetLoadingGate.shared.isLoadingAny
        if wasLoading, loading == false {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sceneGraphNeedsRefresh, object: nil)
            }
        }
        wasLoading = loading
    }
}
