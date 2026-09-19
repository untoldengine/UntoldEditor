//
//  DockTabStrip.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The strip above an area's content: one tab per panel, and the front panel's
/// controls (its filter field and buttons) where the area's placement puts
/// them: beside the tabs, or on a second row across the full width. A single
/// tab reads as the panel's title, several as pills.
struct DockTabStrip: View {
    let state: DockAreaState
    @ObservedObject var layout: EditorDockLayout
    let accessories: AnyView?
    let accessoryPlacement: DockAccessoryPlacement

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(state.tabs) { panel in
                    DockTab(
                        panel: panel,
                        isSelected: panel == state.selected,
                        isAlone: state.tabs.count == 1,
                        layout: layout
                    )
                    .layoutPriority(1)
                }
                Spacer(minLength: 8)
                if accessoryPlacement == .inline, let accessories {
                    accessories
                        .frame(maxWidth: 320)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: DockLayoutGeometry.tabStripHeight)
            if accessoryPlacement == .stacked, let accessories {
                accessories
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .frame(height: DockLayoutGeometry.accessoryRowHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.editorPanelBackground)
        .overlay(alignment: .bottom) {
            Color.editorHairline
                .frame(height: 1)
        }
    }
}
