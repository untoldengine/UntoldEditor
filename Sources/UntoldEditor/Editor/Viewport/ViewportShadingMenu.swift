//
//  ViewportShadingMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The shading dropdown: a sphere swatch and the current shading; the menu
/// lists the lit view and the engine's debug views.
struct ViewportShadingMenu: View {
    let shading: ViewportShading
    let onSelect: (ViewportShading) -> Void

    @State private var showShadings = false

    var body: some View {
        Button {
            showShadings.toggle()
        } label: {
            EditorDropdownLabel(shading.title) {
                Circle()
                    .fill(RadialGradient(colors: [Color.editorTextPrimary, Color.editorTextTertiary], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
                    .frame(width: 9, height: 9)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("What the viewport draws")
        .popover(isPresented: $showShadings, arrowEdge: .bottom) {
            EditorPopupMenu(width: 180) {
                ForEach(ViewportShading.allCases) { candidate in
                    EditorPopupMenuRow(title: candidate.title, isChecked: candidate == shading) {
                        showShadings = false
                        onSelect(candidate)
                    }
                }
            }
        }
    }
}
