//
//  PreviewControl.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// The preview pill at the right of the toolbar, beside the build target: one
/// click shows the scene on the chosen destination, the next ends it. Wide,
/// so that it can be hit with a headset on; lit while the preview goes on.
/// The destination is picked from a chevron once there is more than one to
/// pick from. Hidden where this Mac has no destination, as the View menu's
/// item is.
struct PreviewControl: View {
    @ObservedObject private var session = VisionProPreviewSession.shared
    @ObservedObject private var playback = EditorPlaybackSettings.shared
    @State private var destination: PreviewDestination = .visionPro
    @State private var showsDestinations = false

    var body: some View {
        let destinations = PreviewDestination.available(visionPro: session.state)
        if destinations.isEmpty == false {
            let item = VisionProPreviewSession.menuItem(for: session.state, isPlaying: ViewportCameras.isPlaying)
            EditorPillGroup {
                EditorPillTextButton(
                    title: Self.title(for: session.state),
                    systemImage: destination.systemImage,
                    isActive: session.state == .connecting || session.state == .previewing,
                    isEnabled: item.isEnabled,
                    help: item.title,
                    action: session.toggle
                )
                if destinations.count > 1 {
                    EditorPillMenuButton(
                        title: destination.title,
                        isEnabled: session.state == .idle,
                        help: "Where the preview shows the scene"
                    ) {
                        showsDestinations.toggle()
                    }
                    .popover(isPresented: $showsDestinations, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(destinations) { choice in
                                Button {
                                    destination = choice
                                    showsDestinations = false
                                } label: {
                                    Label(choice.title, systemImage: choice.systemImage)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }
                }
            }
        }
    }

    /// What the button reads in each state of the preview.
    static func title(for state: VisionProPreviewSession.State) -> String {
        switch state {
        case .unavailable, .idle:
            return "Preview"
        case .connecting:
            return "Connecting…"
        case .previewing:
            return "Stop Preview"
        case .ending:
            return "Ending…"
        }
    }
}
