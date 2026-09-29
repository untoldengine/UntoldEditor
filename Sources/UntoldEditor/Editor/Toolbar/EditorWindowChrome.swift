//
//  EditorWindowChrome.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import SwiftUI

/// How the editor's window is set up so that the toolbar row shares its
/// title bar.
enum EditorWindowChrome {
    /// Gives the window the title bar the toolbar row shares.
    static func apply(to window: NSWindow) {
        // Force dark appearance so AppKit-drawn chrome (title bar, native tab
        // strips, segmented controls) matches the dark editor theme.
        window.appearance = NSAppearance(named: .darkAqua)
        // Tint the title bar with the editor background color instead of the
        // default near-black. Transparent title bar lets the window background
        // color (editorBackground) show through.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Color.editorBackground)
        // The editor's toolbar row shares the title bar: the content view runs
        // under it, the title is hidden, and an empty unified toolbar gives the
        // title bar the height that centres the traffic lights in the row.
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        let titleBar = NSToolbar(identifier: "EditorTitleBar")
        titleBar.showsBaselineSeparator = false
        window.toolbar = titleBar
        window.toolbarStyle = .unified
        // The toolbar row drags the window through WindowDragRegion; nothing else
        // does, so a drag in the viewport or in a panel never moves the window.
        window.isMovableByWindowBackground = false
    }

    /// The view that hosts the editor's content in its window. The content
    /// takes no safe area from the window: it draws the toolbar row under the
    /// title bar itself. With a safe area there, the background of whatever
    /// lies under the row, such as a panel's strip, reaches up into it, where
    /// it is clipped away and still in front of the row: the click meant for
    /// Play or Undo goes to the panel.
    static func hostingView<Content: View>(rootView: Content) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.safeAreaRegions = []
        return hostingView
    }
}
