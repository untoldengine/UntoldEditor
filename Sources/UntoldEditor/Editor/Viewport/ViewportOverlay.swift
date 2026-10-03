//
//  ViewportOverlay.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// What the editor draws over the scene in the viewport, each shown or hidden
/// from View > Viewport Overlays. The frame statistics have their own items
/// in the View menu, from before.
enum ViewportOverlay: String, CaseIterable, Identifiable {
    case modeBadge
    case navigationGizmo
    case hints

    var id: String {
        rawValue
    }

    /// The overlay's item in the View menu.
    var title: String {
        switch self {
        case .modeBadge: return "Mode Badge"
        case .navigationGizmo: return "Navigation Gizmo"
        case .hints: return "Shortcut Hints"
        }
    }

    var summary: String {
        switch self {
        case .modeBadge: return "The interaction mode, at the top left of the viewport"
        case .navigationGizmo: return "The world's axes at the top right: click an end to look along it, drag to orbit"
        case .hints: return "How the camera is steered, at the bottom of the viewport"
        }
    }
}
