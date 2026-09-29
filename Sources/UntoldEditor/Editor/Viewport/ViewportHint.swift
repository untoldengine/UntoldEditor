//
//  ViewportHint.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// A shortcut the viewport reminds of in a chip: what it does and how.
struct ViewportHint: Equatable, Identifiable {
    let action: String
    let keys: String

    var id: String {
        action + keys
    }
}

/// The hints of the viewport, from how the camera is steered now.
enum ViewportHints {
    static let frameSelection = ViewportHint(action: "Frame selected", keys: "F")
    static let look = ViewportHint(action: "Look", keys: "Right drag")
    static let fly = ViewportHint(action: "Fly", keys: "W A S D Q E")
    static let pan = ViewportHint(action: "Pan", keys: "⇧ Right drag")
    static let move = ViewportHint(action: "Move", keys: "⌘ Right drag")
    static let orbit = ViewportHint(action: "Orbit", keys: "⌥ Right drag")

    /// What scrolling does without a key held, in a navigation style.
    static func scroll(style: CameraNavigationStyle) -> ViewportHint {
        switch EditorNavigationSettings.scrollAction(style: style, shiftPressed: false, commandPressed: false) {
        case .zoom: return ViewportHint(action: "Zoom", keys: "Scroll")
        case .orbit: return ViewportHint(action: "Orbit", keys: "Scroll")
        case .pan: return ViewportHint(action: "Pan", keys: "Scroll")
        }
    }

    /// The hints by what helps first, so a narrow viewport drops from the
    /// end. Framing is only hinted with something selected to frame.
    static func hints(style: CameraNavigationStyle, hasSelection: Bool) -> [ViewportHint] {
        var hints = hasSelection ? [frameSelection] : []
        hints += [look, fly, scroll(style: style), pan, move]
        // In the Blender style scrolling orbits already.
        if scroll(style: style).action != orbit.action {
            hints.append(orbit)
        }
        return hints
    }
}
