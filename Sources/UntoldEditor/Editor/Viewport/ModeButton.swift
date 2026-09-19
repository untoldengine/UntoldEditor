//
//  ModeButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import SwiftUI
import UntoldEngine

struct ModeButton: View {
    let icon: String
    let label: String
    let mode: TransformManipulationMode
    @Binding var activeMode: TransformManipulationMode

    var isActive: Bool {
        activeMode == mode
    }

    var body: some View {
        Button(action: {
            if gizmoActive == false {
                return
            }

            if activeMode == mode {
                activeMode = .none
            } else {
                activeMode = mode

                if activeMode == .translate {
                    createGizmo(name: "translateGizmo")
                } else if activeMode == .rotate {
                    createGizmo(name: "rotateGizmo")
                } else if activeMode == .scale {
                    createGizmo(name: "scaleGizmo")
                }
            }
        }) {
            HStack {
                Image(systemName: icon)
                // Text(label)
            }
            .padding(8)
            .background(isActive ? Color.editorAccentSoft : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
