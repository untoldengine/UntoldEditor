//
//  InteractionModeMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The mode dropdown at the left of the viewport header: the mode's dot and
/// name, and a menu of the modes with what each is for.
struct InteractionModeMenu: View {
    let mode: InteractionMode

    @State private var showModes = false

    var body: some View {
        Button {
            showModes.toggle()
        } label: {
            EditorDropdownLabel(mode.title, minWidth: 112) {
                Circle()
                    .fill(mode.dotColor)
                    .frame(width: 8, height: 8)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("How the viewport is used")
        .popover(isPresented: $showModes, arrowEdge: .bottom) {
            EditorPopupMenu {
                ForEach(InteractionMode.allCases) { candidate in
                    EditorPopupMenuRow(title: candidate.title, subtitle: candidate.subtitle, isChecked: candidate == mode) {
                        showModes = false
                    }
                }
            }
        }
    }
}
