//
//  BuildTargetMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The build target pill of the toolbar: the platform's icon, its name and a
/// chevron, styled like the History button; a click opens the list of targets.
struct BuildTargetMenu: View {
    @Binding var target: EditorBuildTarget
    @State private var showTargets = false

    var body: some View {
        EditorPillGroup {
            EditorPillMenuButton(
                title: target.title,
                systemImage: target.systemImage,
                help: "The platform the editor previews and the status bar shows. Building for it is not part of the editor yet."
            ) {
                showTargets.toggle()
            }
            .popover(isPresented: $showTargets, arrowEdge: .bottom) {
                BuildTargetPopover(target: $target) {
                    showTargets = false
                }
            }
        }
    }
}
