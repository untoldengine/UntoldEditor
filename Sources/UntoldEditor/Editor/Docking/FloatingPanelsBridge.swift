//
//  FloatingPanelsBridge.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Puts the layout's floating panels in windows of their own, fed with the
/// panels' content from the root view on every one of its updates, so a
/// floating panel shows the same state as a docked one and its changes flow
/// back the same way. Draws nothing in the editor window; its view only finds
/// that window, which the floating windows attach to.
struct FloatingPanelsBridge: NSViewRepresentable {
    /// The panels to float, in order; none while the editor shows the viewport alone.
    let panels: [PanelID]
    let layout: EditorDockLayout
    let content: (PanelID) -> AnyView
    let accessories: (PanelID) -> AnyView?

    func makeCoordinator() -> Coordinator {
        Coordinator(windows: FloatingPanelWindows(layout: layout))
    }

    func makeNSView(context: Context) -> FloatingPanelsAnchorView {
        let view = FloatingPanelsAnchorView()
        view.isHidden = true
        let coordinator = context.coordinator
        view.onMoveToWindow = {
            coordinator.syncSoon()
        }
        return view
    }

    func updateNSView(_ view: FloatingPanelsAnchorView, context: Context) {
        context.coordinator.update(panels: panels, content: content, accessories: accessories, anchor: view)
    }

    static func dismantleNSView(_: FloatingPanelsAnchorView, coordinator: Coordinator) {
        coordinator.windows.closeAll()
    }

    /// Holds the latest panels and content and syncs the windows a moment
    /// later, outside SwiftUI's update: making or closing windows there is
    /// work AppKit should not do in the middle of a layout pass.
    @MainActor
    final class Coordinator {
        let windows: FloatingPanelWindows
        private var panels: [PanelID] = []
        private var content: (PanelID) -> AnyView = { _ in AnyView(EmptyView()) }
        private var accessories: (PanelID) -> AnyView? = { _ in nil }
        private weak var anchor: NSView?
        private var isSyncScheduled = false

        init(windows: FloatingPanelWindows) {
            self.windows = windows
        }

        func update(
            panels: [PanelID],
            content: @escaping (PanelID) -> AnyView,
            accessories: @escaping (PanelID) -> AnyView?,
            anchor: NSView
        ) {
            self.panels = panels
            self.content = content
            self.accessories = accessories
            self.anchor = anchor
            syncSoon()
        }

        func syncSoon() {
            guard isSyncScheduled == false else { return }
            isSyncScheduled = true
            Task { @MainActor [weak self] in
                guard let self else { return }
                isSyncScheduled = false
                sync()
            }
        }

        func sync() {
            guard let parent = anchor?.window else { return }
            windows.sync(panels: panels, parent: parent) { panel in
                FloatingPanelContent(panel: panel, content: content(panel), accessories: accessories(panel))
            }
        }
    }
}
