//
//  FloatingPanelDockButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The button in a floating panel's title bar that puts the panel back in the
/// area it came from: the icon alone, the words in its tooltip.
struct FloatingPanelDockButton: View {
    let panel: PanelID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Dock", systemImage: "rectangle.bottomthird.inset.filled")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Dock")
        .buttonStyle(.accessoryBar)
        .controlSize(.small)
        .help("Put \(panel.title) back in its area")
        .padding(.trailing, 8)
    }
}
