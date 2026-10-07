//
//  VisionProPreviewScene.swift
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

    /// The space the headset shows: the scene, drawn by this Mac. The app
    /// declares it; the session opens and closes it.
    @available(macOS 26.0, *)
    struct VisionProPreviewScene: SwiftUI.Scene {
        static let id = "untold.editor.visionProPreview"

        var body: some SwiftUI.Scene {
            RemoteImmersiveSpace(id: Self.id) {
                VisionProPreviewContent()
            }
            .immersionStyle(selection: .constant(.full), in: .full)
        }
    }
#endif
