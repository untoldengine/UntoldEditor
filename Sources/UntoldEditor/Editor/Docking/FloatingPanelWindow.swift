//
//  FloatingPanelWindow.swift
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

/// A panel's window while it floats: the panel's title in the title bar, a
/// Dock button beside it, and the panel under it with its controls. A floating
/// panel, so it stays above the editor window on whichever screen it is taken
/// to, also beside a full-screen editor, and hides with the app. Reports its
/// moves, its resizes and its closing to whoever made it.
@MainActor
final class FloatingPanelWindow: NSObject, NSWindowDelegate {
    let panel: PanelID
    let window: NSPanel
    private let hostingView: NSHostingView<FloatingPanelContent>
    private let onDock: () -> Void
    private let onClose: () -> Void
    private let onFrameChange: (CGRect) -> Void

    init(
        panel: PanelID,
        frame: CGRect,
        content: FloatingPanelContent,
        onDock: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onFrameChange: @escaping (CGRect) -> Void
    ) {
        self.panel = panel
        self.onDock = onDock
        self.onClose = onClose
        self.onFrameChange = onFrameChange
        hostingView = NSHostingView(rootView: content)
        // The window keeps the size the user gives it; the panel fills it.
        hostingView.sizingOptions = []
        window = NSPanel(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = panel.title
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        // Above the editor window wherever it goes, not above other apps, and
        // listed in the Window menu so it can be found on another screen.
        window.isFloatingPanel = true
        window.hidesOnDeactivate = true
        window.isExcludedFromWindowsMenu = false
        window.collectionBehavior.insert(.fullScreenAuxiliary)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(Color.editorPanelBackground)
        window.contentMinSize = panel.minimumSize
        window.contentView = hostingView
        // The frame goes in before the delegate listens: the first placement
        // is not a move to remember.
        window.setFrame(frame, display: false)
        window.delegate = self

        let dock = NSTitlebarAccessoryViewController()
        dock.layoutAttribute = .trailing
        let button = NSHostingView(rootView: FloatingPanelDockButton(panel: panel) { [weak self] in
            self?.dock()
        })
        button.frame.size = button.fittingSize
        dock.view = button
        window.addTitlebarAccessoryViewController(dock)
    }

    /// What the window shows.
    var content: FloatingPanelContent {
        hostingView.rootView
    }

    /// Shows the panel's current content.
    func show(_ content: FloatingPanelContent) {
        hostingView.rootView = content
    }

    /// What the Dock button does: puts the panel back in its area.
    func dock() {
        onDock()
    }

    /// Closes the window because its panel docked or closed in the layout:
    /// nothing is reported back.
    func closeQuietly() {
        window.delegate = nil
        window.close()
    }

    // MARK: - NSWindowDelegate

    func windowDidMove(_: Notification) {
        onFrameChange(window.frame)
    }

    func windowDidResize(_: Notification) {
        onFrameChange(window.frame)
    }

    func windowWillClose(_: Notification) {
        onClose()
    }
}
