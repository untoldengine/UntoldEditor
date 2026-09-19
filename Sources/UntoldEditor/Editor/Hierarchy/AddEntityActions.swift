//
//  AddEntityActions.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldEngine

/// The "add entity" actions, bundled so the same menu can be reused by the
/// bottom "+" toolbar and the right-click context menu.
struct AddEntityActions {
    var empty: () -> Void = {}
}

/// Cube/Sphere/Plane and all four light types moved to the Asset Browser's
/// Primitives and Lights shelves (see AssetBrowserView.swift), which drag as well
/// as click; Empty Entity stays here since it has no visual or component to
/// preview, so it doesn't fit the "drop at a point" pattern.
func addEntityMenuItems(_ actions: AddEntityActions) -> some View {
    Button("Empty Entity", systemImage: "plus") { actions.empty() }
}
