//
//  EditorPanelRegistry.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Builds any panel from its id, so the same panel can appear in whichever
/// area the layout puts it in. The root view supplies the builders, since the
/// panels read its state and call its actions.
struct EditorPanelRegistry {
    /// The panel's content.
    let content: (PanelID) -> AnyView
    /// The controls that go with the panel when it is in front, such as its
    /// filter field; nil for a panel that has none.
    let accessories: (PanelID) -> AnyView?
}
