//
//  VisualDebugger.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Metal

struct DebugTextureEntry {
    let name: String
    let texture: MTLTexture
}

class DebugTextureRegistry {
    static var entries: [DebugTextureEntry] = []

    static func register(name: String, texture: MTLTexture) {
        entries.append(DebugTextureEntry(name: name, texture: texture))
    }

    static func get(byName name: String) -> MTLTexture? {
        entries.first(where: { $0.name == name })?.texture
    }

    static func allNames() -> [String] {
        entries.map(\.name)
    }

    static func reset() {
        entries.removeAll()
    }
}
