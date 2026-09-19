//
//  DockArea.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics
import Foundation

/// The three areas around the viewport a panel can dock in. Each shows its
/// panels as tabs; an area with no panels takes no space.
enum DockArea: String, Codable, CaseIterable, Identifiable {
    case left
    case right
    case bottom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .left: return "Left Area"
        case .right: return "Right Area"
        case .bottom: return "Bottom Area"
        }
    }

    /// The width of a side area or the height of the bottom one, from the mockup.
    var defaultLength: CGFloat {
        switch self {
        case .left: return 250
        case .right: return 320
        case .bottom: return 250
        }
    }

    /// Side areas are measured by width, the bottom one by height.
    var isSide: Bool {
        self != .bottom
    }

    /// Where a panel's controls (its filter field and buttons) go in the area's
    /// tab strip: beside the tabs where the strip is wide, under them where it
    /// is narrow, so they never push a tab out.
    var accessoryPlacement: DockAccessoryPlacement {
        isSide ? .stacked : .inline
    }
}

/// How an area's tab strip places the front panel's controls.
enum DockAccessoryPlacement {
    /// On the tabs' row, right-aligned.
    case inline
    /// On a second row under the tabs, across the full width.
    case stacked
}

/// The panels of one area, the one in front, and the area's length.
struct DockAreaState: Codable, Equatable {
    var tabs: [PanelID]
    var selected: PanelID?
    var length: CGFloat

    init(tabs: [PanelID] = [], selected: PanelID? = nil, length: CGFloat) {
        self.tabs = tabs
        self.selected = selected ?? tabs.first
        self.length = length
    }

    var isVisible: Bool {
        tabs.isEmpty == false
    }
}

/// The whole docking layout: the three areas around the viewport.
struct DockLayoutState: Codable, Equatable {
    var left: DockAreaState
    var right: DockAreaState
    var bottom: DockAreaState

    subscript(area: DockArea) -> DockAreaState {
        get {
            switch area {
            case .left: return left
            case .right: return right
            case .bottom: return bottom
            }
        }
        set {
            switch area {
            case .left: left = newValue
            case .right: right = newValue
            case .bottom: bottom = newValue
            }
        }
    }

    /// Every docked panel, left to right then bottom.
    var panels: [PanelID] {
        left.tabs + right.tabs + bottom.tabs
    }

    func area(of panel: PanelID) -> DockArea? {
        DockArea.allCases.first { self[$0].tabs.contains(panel) }
    }
}
