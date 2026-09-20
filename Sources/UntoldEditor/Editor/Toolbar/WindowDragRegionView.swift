//
//  WindowDragRegionView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit

/// A transparent view that drags the window when the mouse goes down on it,
/// and zooms or minimises it on a double-click as the system's title bar does.
/// It stands in for the title bar under the toolbar row; the controls on top
/// of it take their own clicks first.
final class WindowDragRegionView: NSView {
    enum DoubleClickAction: Equatable {
        case zoom
        case minimize
        case none
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            switch Self.doubleClickAction(preference: UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick")) {
            case .zoom:
                window?.performZoom(nil)
            case .minimize:
                window?.performMiniaturize(nil)
            case .none:
                break
            }
            return
        }
        window?.performDrag(with: event)
    }

    /// What a double-click does, from the system's "Double-click a window's
    /// title bar to" preference: zoom unless the preference says otherwise.
    nonisolated static func doubleClickAction(preference: String?) -> DoubleClickAction {
        switch preference {
        case "Minimize": return .minimize
        case "None": return .none
        default: return .zoom
        }
    }
}
