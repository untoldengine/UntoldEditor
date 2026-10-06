//
//  VisionProPreviewActions.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The part of the bridge that has the actions: they are environment values
/// of a SwiftUI view, so a view keeps them for the session.
@available(macOS 26.0, *)
struct VisionProPreviewActions: View {
    @Environment(\.supportsRemoteScenes) private var supportsRemoteScenes
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear(perform: handOver)
            .onChange(of: supportsRemoteScenes) { _, _ in
                handOver()
            }
    }

    private func handOver() {
        let session = VisionProPreviewSession.shared
        #if canImport(CompositorServices)
            let openImmersiveSpace = openImmersiveSpace
            session.openSpace = {
                let result = await openImmersiveSpace(id: VisionProPreviewScene.id)
                switch result {
                case .opened:
                    return true
                case .userCancelled:
                    Logger.log(message: "Vision Pro preview: the request was cancelled.")
                    return false
                case .error:
                    Logger.log(message: "Vision Pro preview: the system could not open the space on a headset.")
                    return false
                @unknown default:
                    Logger.log(message: "Vision Pro preview: the system answered \(result).")
                    return false
                }
            }
        #endif
        let dismissImmersiveSpace = dismissImmersiveSpace
        session.dismissSpace = {
            await dismissImmersiveSpace()
        }
        session.setAvailable(supportsRemoteScenes)
    }
}
