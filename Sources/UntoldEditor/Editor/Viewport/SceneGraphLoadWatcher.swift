//
//  SceneGraphLoadWatcher.swift
//  UntoldEditor
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
