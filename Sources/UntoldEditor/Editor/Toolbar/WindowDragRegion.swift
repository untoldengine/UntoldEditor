//
//  WindowDragRegion.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Hosts `WindowDragRegionView` behind the toolbar row, so the row moves the
/// window the way a title bar does.
struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context _: Context) -> WindowDragRegionView {
        WindowDragRegionView()
    }

    func updateNSView(_: WindowDragRegionView, context _: Context) {}
}
