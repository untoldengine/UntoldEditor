//
//  EngineStereoMode.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import MetalKit
import simd
import UntoldEngine

/// The engine's render targets for the headset or for the viewport. The
/// engine makes a renderer of its own for a headset (`createXR`), which the
/// editor cannot use: it would be a second renderer over the open scene,
/// with a camera and a light of its own. The editor keeps its one renderer
/// and switches its targets: two eyes of the headset's size, or the viewport.
extension UntoldRenderer {
    /// Switches to stereo. The eyes' size is not known until the headset
    /// hands over its first frame; `fitStereoTargets(to:)` sizes them then.
    func enterStereo() {
        renderInfo.isXRStereoMode = true
        renderInfo.currentEye = 0
    }

    /// Sizes the targets to one eye, when the eye's size is not what they
    /// have. True when they were made again.
    @discardableResult
    func fitStereoTargets(to eyeSize: simd_float2) -> Bool {
        guard renderInfo.viewPort != eyeSize else {
            return false
        }
        renderInfo.viewPort = eyeSize
        initSizeableResources()
        return true
    }

    /// Switches back to the viewport's targets, at its size, and to its
    /// projection.
    func leaveStereo(viewport: MTKView) {
        renderInfo.isXRStereoMode = false
        renderInfo.currentEye = 0
        renderInfo.viewPort = simd_float2(Float(viewport.drawableSize.width), Float(viewport.drawableSize.height))
        initSizeableResources()
        mtkView(viewport, drawableSizeWillChange: viewport.drawableSize)
    }
}
