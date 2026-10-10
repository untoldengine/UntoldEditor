//
//  FloatingPanelWindows.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit

/// Keeps one window per floating panel, matching the layout: makes a window
/// when a panel floats, at its remembered frame when that is still on a
/// screen, hands every window its panel's current content, and closes a
/// window when its panel docks or closes. A window the user closes closes its
/// panel, its Dock button docks the panel, and its frame is remembered as it
/// moves. The windows close with the editor window.
@MainActor
final class FloatingPanelWindows {
    private let layout: EditorDockLayout
    private let screens: () -> [CGRect]
    private let ordersFront: Bool
    private(set) var windows: [PanelID: FloatingPanelWindow] = [:]
    private weak var parent: NSWindow?
    private var parentClosing: NSObjectProtocol?

    /// `screens` are the frames a remembered window may open on; `ordersFront`
    /// is off in tests, which have no screen to show a window on.
    init(
        layout: EditorDockLayout,
        screens: @escaping () -> [CGRect] = { NSScreen.screens.map(\.visibleFrame) },
        ordersFront: Bool = true
    ) {
        self.layout = layout
        self.screens = screens
        self.ordersFront = ordersFront
    }

    deinit {
        if let parentClosing {
            NotificationCenter.default.removeObserver(parentClosing)
        }
    }

    /// Makes the windows match `panels`, the layout's floating panels in order,
    /// each showing `content` for its panel; `parent` is the editor window a
    /// new window opens beside and closes with.
    func sync(panels: [PanelID], parent: NSWindow, content: (PanelID) -> FloatingPanelContent) {
        watch(parent)
        for (panel, window) in windows where panels.contains(panel) == false {
            windows[panel] = nil
            window.closeQuietly()
        }
        for (index, panel) in panels.enumerated() {
            if let window = windows[panel] {
                window.show(content(panel))
                continue
            }
            let remembered = layout.floatingFrame(of: panel)
            let frame = remembered.flatMap { FloatingPanelFrames.isReachable($0, on: screens()) ? $0 : nil }
                ?? FloatingPanelFrames.defaultFrame(for: panel, beside: parent.frame, index: index)
            let window = FloatingPanelWindow(
                panel: panel,
                frame: frame,
                content: content(panel),
                onDock: { [layout] in
                    layout.dock(panel)
                },
                onClose: { [weak self, layout] in
                    self?.windows[panel] = nil
                    // Closed by the user: the panel closes. Closed from here,
                    // the layout has already moved on and nothing changes.
                    if layout.isFloating(panel) {
                        layout.close(panel)
                    }
                },
                onFrameChange: { [layout] frame in
                    layout.setFloatingFrame(frame, of: panel)
                }
            )
            windows[panel] = window
            if ordersFront {
                window.window.orderFront(nil)
            }
        }
    }

    /// Closes every window and leaves the layout as it is, so the panels float
    /// again next time.
    func closeAll() {
        for window in windows.values {
            window.closeQuietly()
        }
        windows = [:]
    }

    private func watch(_ editorWindow: NSWindow) {
        guard parent !== editorWindow else { return }
        parent = editorWindow
        if let parentClosing {
            NotificationCenter.default.removeObserver(parentClosing)
        }
        parentClosing = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: editorWindow, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.closeAll()
            }
        }
    }
}
