//
//  FloatingPanelsAnchorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit

/// The view the floating panels bridge puts in the editor window: zero-sized
/// and hidden, it only tells the bridge when it has joined the window the
/// floating windows attach to.
final class FloatingPanelsAnchorView: NSView {
    var onMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onMoveToWindow?()
    }
}
