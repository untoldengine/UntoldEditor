//
//  EditorViewportHost.swift
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

/// SwiftUI wrapper for `EditorViewportHostView`. Runs `onInit` once, when the
/// host is created, like the engine's `SceneView.onInit`.
struct EditorViewportHost: NSViewRepresentable {
    let renderer: UntoldRenderer
    let onInit: @MainActor () -> Void

    final class Coordinator {
        var didRunInit = false
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> EditorViewportHostView {
        let host = EditorViewportHostView(metalView: renderer.metalView)
        if !context.coordinator.didRunInit {
            context.coordinator.didRunInit = true
            onInit()
        }
        return host
    }

    func updateNSView(_: EditorViewportHostView, context _: Context) {}
}
