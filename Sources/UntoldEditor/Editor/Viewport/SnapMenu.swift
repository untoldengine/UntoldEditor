//
//  SnapMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The snap pill of the viewport header, and the menu with the switches and
/// the steps for moves, rotations and scales.
struct SnapMenu: View {
    @ObservedObject var snap: EditorSnapSettings

    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings.toggle()
        } label: {
            EditorDropdownLabel(snap.summary) {
                Image(systemName: "grid")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(snap.isEnabled ? .editorAccent : .editorTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Snapping: the steps a drag lands on")
        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
            EditorPopupMenu(width: 290) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Toggle("", isOn: $snap.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(.editorAccent)
                            .controlSize(.small)
                        Text("Snap")
                            .font(EditorType.title)
                            .foregroundColor(.editorTextPrimary)
                        Spacer()
                    }
                    SnapStepRow(title: "Move", isOn: $snap.snapsMove, step: $snap.gridStep, steps: EditorSnapSettings.gridSteps) {
                        "\(EditorSnapSettings.format($0)) m"
                    }
                    SnapStepRow(title: "Rotate", isOn: $snap.snapsRotate, step: $snap.rotationStep, steps: EditorSnapSettings.rotationSteps) {
                        "\(Int($0))°"
                    }
                    SnapStepRow(title: "Scale", isOn: $snap.snapsScale, step: $snap.scaleStep, steps: EditorSnapSettings.scaleSteps) {
                        EditorSnapSettings.format($0)
                    }
                }
                .padding(10)
            }
        }
    }
}
