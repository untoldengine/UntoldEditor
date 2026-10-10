//
//  FloatingPanelContent.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// What a floating panel's window shows under its title bar: the panel's
/// controls on a row of their own, as a side area places them, then the panel.
struct FloatingPanelContent: View {
    let panel: PanelID
    let content: AnyView
    let accessories: AnyView?

    var body: some View {
        VStack(spacing: 0) {
            if let accessories {
                accessories
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .frame(height: DockLayoutGeometry.accessoryRowHeight)
                    .overlay(alignment: .bottom) {
                        Color.editorHairline
                            .frame(height: 1)
                    }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        }
        .background(Color.editorPanelBackground)
    }
}
