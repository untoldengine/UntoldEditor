//
//  TransformManipulationToolbar.swift
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

struct TransformManipulationToolbar: View {
    @ObservedObject var controller: EditorController

    var body: some View {
        HStack {
            Spacer()

            // Centered mode buttons
            HStack(spacing: 5) {
                ModeButton(
                    icon: "arrow.up.and.down.and.arrow.left.and.right",
                    label: "Translate",
                    mode: .translate,
                    activeMode: $controller.activeMode
                )
                ModeButton(
                    icon: "rotate.3d",
                    label: "Rotate",
                    mode: .rotate,
                    activeMode: $controller.activeMode
                )
                ModeButton(
                    icon: "arrow.up.left.and.down.right.magnifyingglass",
                    label: "Scale",
                    mode: .scale,
                    activeMode: $controller.activeMode
                )
            }

            Spacer()
        }
        .padding(.horizontal)
        .background(Color.editorFill)
        .cornerRadius(5)
    }
}
