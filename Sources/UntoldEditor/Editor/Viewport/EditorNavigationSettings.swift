//
//  EditorNavigationSettings.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// How scrolling over the viewport moves the scene camera. The right button
/// steers it the same way in every style: a drag looks around, ⇧ pans, ⌘ moves
/// the camera forward and back, ⌥ orbits.
public enum CameraNavigationStyle: String, CaseIterable {
    /// The scroll wheel and a pinch zoom.
    case classic
    /// Blender-like: scrolling (wheel or two-finger swipe) orbits, ⇧-scroll pans,
    /// ⌘-scroll zooms.
    case blender

    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .blender: return "Blender"
        }
    }

    public var summary: String {
        switch self {
        case .classic: return "Scroll zooms"
        case .blender: return "Scroll orbits · ⇧ Scroll pans · ⌘ Scroll zooms"
        }
    }
}

/// What a right-button drag on the viewport does to the scene camera.
public enum CameraDragAction: Equatable {
    /// Turns the view where the camera stands, as the mouse does in a game.
    case look
    /// Slides the camera along the view plane.
    case pan
    /// Moves the camera forward and back.
    case zoom
    /// Turns the camera around the point ahead of it.
    case orbit
    /// No drag is steering the camera.
    case none
}

/// What a scroll wheel or two-finger swipe over the viewport does to the camera.
public enum CameraScrollAction: Equatable {
    case zoom
    case orbit
    case pan
}

/// Camera navigation preferences shared between the AppKit menu bar, SwiftUI
/// and the input system. Persisted in `UserDefaults`.
public final class EditorNavigationSettings: ObservableObject {
    public static let shared = EditorNavigationSettings(defaults: .standard)

    static let styleDefaultsKey = "editor.camera.navigationStyle"

    @Published public var style: CameraNavigationStyle {
        didSet {
            defaults.set(style.rawValue, forKey: Self.styleDefaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.styleDefaultsKey),
           let saved = CameraNavigationStyle(rawValue: raw)
        {
            style = saved
        } else {
            style = .classic
        }
    }

    /// What the right button's drags do, for the hints and the tooltips.
    public static let dragSummary = "Right drag looks around · ⇧ pans · ⌘ moves · ⌥ orbits"

    /// Resolves what a right-button drag does from the modifiers held when it
    /// starts: nothing held looks around, ⇧ pans, ⌘ moves the camera forward
    /// and back, ⌥ orbits the point ahead. ⇧ wins over ⌘, and ⌘ over ⌥.
    public static func dragAction(shiftPressed: Bool, commandPressed: Bool, optionPressed: Bool) -> CameraDragAction {
        if shiftPressed {
            return .pan
        }
        if commandPressed {
            return .zoom
        }
        return optionPressed ? .orbit : .look
    }

    /// Resolves what scrolling does. The classic style zooms, as it always has.
    /// The Blender style navigates without any button held: a plain wheel or
    /// two-finger swipe orbits with both axes, ⇧-scroll pans along the view
    /// plane and ⌘-scroll zooms. ⇧ wins over ⌘, as it does for drags.
    public static func scrollAction(style: CameraNavigationStyle, shiftPressed: Bool, commandPressed: Bool) -> CameraScrollAction {
        switch style {
        case .classic:
            return .zoom
        case .blender:
            if shiftPressed {
                return .pan
            }
            return commandPressed ? .zoom : .orbit
        }
    }

    /// Convenience over `scrollAction(style:...)` using the current style.
    public func scrollAction(shiftPressed: Bool, commandPressed: Bool) -> CameraScrollAction {
        Self.scrollAction(style: style, shiftPressed: shiftPressed, commandPressed: commandPressed)
    }
}
