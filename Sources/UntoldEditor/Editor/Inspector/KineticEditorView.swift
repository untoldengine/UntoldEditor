//
//  KineticEditorView.swift
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

struct KineticEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Kinetic System")

        if hasComponent(entityId: entityId, componentType: KineticComponent.self) {
            let mass = getMass(entityId: entityId)
            TextInputNumberView(label: "Mass", value: Binding(
                get: { mass },
                set: { newMass in
                    setMass(entityId: entityId, mass: newMass)
                    refreshView()
                }
            ))
        }
    }
}
