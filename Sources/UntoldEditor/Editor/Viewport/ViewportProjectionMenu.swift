//
//  ViewportProjectionMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The projection dropdown: the free camera and the preset views along an axis.
struct ViewportProjectionMenu: View {
    let projection: ViewportProjection
    let onSelect: (ViewportProjection) -> Void

    @State private var showProjections = false

    var body: some View {
        Button {
            showProjections.toggle()
        } label: {
            EditorDropdownLabel(projection.title)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Where the camera looks from")
        .popover(isPresented: $showProjections, arrowEdge: .bottom) {
            EditorPopupMenu(width: 180) {
                ForEach(ViewportProjection.allCases) { candidate in
                    EditorPopupMenuRow(title: candidate.title, isChecked: candidate == projection) {
                        showProjections = false
                        onSelect(candidate)
                    }
                }
            }
        }
    }
}
