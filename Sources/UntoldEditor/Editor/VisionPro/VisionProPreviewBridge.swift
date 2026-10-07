//
//  VisionProPreviewBridge.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Hands SwiftUI's actions that open and close the remote space to the
/// session, which the View menu drives. Draws nothing. Before macOS 26 there
/// is nothing to hand over and the session stays unavailable.
struct VisionProPreviewBridge: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            VisionProPreviewActions()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }
}
