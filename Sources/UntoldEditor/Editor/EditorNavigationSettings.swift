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

/// How a left-button drag on the viewport moves the scene camera.
public enum CameraNavigationStyle: String, CaseIterable {
    /// Drag orbits. Zoom comes from the scroll wheel / pinch only; modifier
    /// keys do not change what a drag does.
    case classic
    /// Blender-like: drag orbits, ⇧-drag pans, ⌘-drag zooms (dolly).
    case blender

    public var title: String {
        switch self {
        case .classic: return "Classic"
        case .blender: return "Blender"
        }
    }

    public var summary: String {
        switch self {
        case .classic: return "Drag orbits · Scroll zooms"
        case .blender: return "Drag orbits · ⇧ Drag pans · ⌘ Drag zooms"
        }
    }
}

/// What a viewport drag should do to the scene camera.
public enum CameraDragAction: Equatable {
    case orbit
    case pan
    case zoom
    /// The drag is reserved for something else (entity manipulation), so the
    /// camera must stay put.
    case none
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

    /// Resolves what a left-button drag does given the active style and the
    /// modifier / selection state at the moment the drag starts.
    ///
    /// ⇧-drag while an entity is selected is reserved for manipulating that
    /// entity without the camera moving underneath it, in every style. With
    /// nothing selected the Blender style turns ⇧-drag into a pan and ⌘-drag
    /// into a zoom; the classic style always orbits.
    public static func dragAction(
        style: CameraNavigationStyle,
        shiftPressed: Bool,
        commandPressed: Bool,
        hasSelection: Bool
    ) -> CameraDragAction {
        if shiftPressed, hasSelection {
            return .none
        }

        switch style {
        case .classic:
            return .orbit
        case .blender:
            if shiftPressed {
                return .pan
            }
            if commandPressed {
                return .zoom
            }
            return .orbit
        }
    }

    /// Convenience over `dragAction(style:...)` using the current style.
    public func dragAction(shiftPressed: Bool, commandPressed: Bool, hasSelection: Bool) -> CameraDragAction {
        Self.dragAction(style: style, shiftPressed: shiftPressed, commandPressed: commandPressed, hasSelection: hasSelection)
    }
}
