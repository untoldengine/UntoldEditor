//
//  NavigationDragHandlers.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
import UntoldEngine

/// What a navigation control of the viewport does with a drag on it: the
/// camera is told when the drag begins, of each step and when it ends.
struct NavigationDragHandlers {
    let began: () -> Void
    /// A step in points, x to the right and y up the screen.
    let moved: (simd_float2) -> Void
    let ended: () -> Void

    /// The handlers that steer the editor's camera as the right button does
    /// with the modifier of `action` held.
    static func camera(_ action: CameraDragAction) -> NavigationDragHandlers {
        NavigationDragHandlers(
            began: { InputSystem.shared.beginCameraDrag(as: action) },
            moved: { InputSystem.shared.moveCameraDrag(by: $0) },
            ended: { InputSystem.shared.endCameraDrag() }
        )
    }
}
