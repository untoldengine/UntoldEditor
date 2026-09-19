//
//  TileMeshInspectorEntry.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

struct TileMeshInspectorEntry: Identifiable {
    let entityId: EntityID
    let meshIndex: Int
    let name: String
    let submeshCount: Int

    var id: String {
        "\(entityId)-\(meshIndex)"
    }

    var displayName: String {
        name.isEmpty ? "Mesh \(meshIndex + 1)" : name
    }
}
