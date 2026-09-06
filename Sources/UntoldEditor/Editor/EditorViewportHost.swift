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

/// Hosts the engine's Metal view in the editor viewport.
///
/// Normally the Metal view fills the host. While a resize hold is active
/// (`EditorViewportResizePolicy.beginResizeHold(of:)`) the Metal view is kept
/// at a larger, fixed size and centred, and the host clips it: the frozen frame
/// then extends past the visible area, so growing the window or hiding a panel
/// reveals more scene instead of a blank band.
final class EditorViewportHostView: NSView {
    let metalView: MTKView

    /// Size to keep the Metal view at, centred, while a hold is active. Nil
    /// lets it fill the host again. Applied immediately.
    var heldMetalViewSize: CGSize? {
        didSet {
            guard heldMetalViewSize != oldValue else { return }
            placeMetalView()
        }
    }

    init(metalView: MTKView) {
        self.metalView = metalView
        super.init(frame: .zero)
        clipsToBounds = true
        addSubview(metalView)
        placeMetalView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        placeMetalView()
    }

    override func layout() {
        super.layout()
        placeMetalView()
    }

    private func placeMetalView() {
        let frame = Self.metalViewFrame(in: bounds, held: heldMetalViewSize)
        if metalView.frame != frame {
            metalView.frame = frame
        }
    }

    /// The Metal view fills `bounds`, or keeps `held` and sits centred on whole
    /// points so the frozen frame is not resampled.
    static func metalViewFrame(in bounds: CGRect, held: CGSize?) -> CGRect {
        guard let held else { return bounds }
        return CGRect(
            x: floor(bounds.midX - held.width / 2),
            y: floor(bounds.midY - held.height / 2),
            width: held.width,
            height: held.height
        )
    }
}

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
