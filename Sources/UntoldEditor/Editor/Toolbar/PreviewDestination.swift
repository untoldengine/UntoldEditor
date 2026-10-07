//
//  PreviewDestination.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where the toolbar's preview shows the scene, besides the viewport: an
/// Apple Vision Pro nearby. A window of its own and the full screen are the
/// destinations to come; the control offers the choice once there is one.
enum PreviewDestination: String, CaseIterable, Identifiable {
    case visionPro

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .visionPro:
            return "Apple Vision Pro"
        }
    }

    var systemImage: String {
        switch self {
        case .visionPro:
            return "visionpro"
        }
    }

    /// The destinations this Mac can preview on now.
    static func available(visionPro: VisionProPreviewSession.State) -> [PreviewDestination] {
        visionPro == .unavailable ? [] : [.visionPro]
    }
}
