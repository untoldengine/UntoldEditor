//
//  HierarchyRowClick.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit

/// What a click on a row of the hierarchy does.
enum HierarchyRowClick: Equatable {
    /// Nothing: from Play to Stop the hierarchy selects nothing, as the
    /// viewport does.
    case none
    /// The row alone is the selection.
    case select
    /// The row joins the selection, or leaves it when it was selected.
    case toggle

    /// A click with ⇧ or ⌘ held adds to the selection, as a ⇧ click in the
    /// viewport does and as ⌘ does in any list.
    static func click(isPlaying: Bool, modifiers: NSEvent.ModifierFlags) -> HierarchyRowClick {
        guard isPlaying == false else {
            return .none
        }
        return modifiers.contains(.shift) || modifiers.contains(.command) ? .toggle : .select
    }
}
