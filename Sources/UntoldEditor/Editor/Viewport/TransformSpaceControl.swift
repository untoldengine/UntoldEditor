//
//  TransformSpaceControl.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// World / Local: which axes the gizmo works along.
struct TransformSpaceControl: View {
    let space: TransformSpace
    let onSelect: (TransformSpace) -> Void

    var body: some View {
        EditorSegmented(
            options: TransformSpace.allCases,
            selection: Binding(get: { space }, set: onSelect),
            label: { $0.title },
            help: { $0.help }
        )
    }
}
