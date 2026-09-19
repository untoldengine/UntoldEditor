//
//  PanelID.swift
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

/// The panels of the editor window: the areas a user can dock left, right or
/// below the viewport, move between those areas, resize and hide. The viewport
/// is a panel too, though it stays in the centre and never closes.
enum PanelID: String, Codable, CaseIterable, Identifiable {
    case hierarchy
    case viewport
    case inspector
    case assets
    case explore
    case console
    case tasks
    case plugins

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .hierarchy: return "Hierarchy"
        case .viewport: return "Viewport"
        case .inspector: return "Inspector"
        case .assets: return "Assets"
        case .explore: return "Explore"
        case .console: return "Console"
        case .tasks: return "Tasks"
        case .plugins: return "Plugins"
        }
    }

    var systemImage: String {
        switch self {
        case .hierarchy: return "list.bullet.indent"
        case .viewport: return "cube.transparent"
        case .inspector: return "slider.horizontal.3"
        case .assets: return "shippingbox"
        case .explore: return "square.grid.2x2"
        case .console: return "terminal"
        case .tasks: return "list.bullet.rectangle"
        case .plugins: return "puzzlepiece.extension"
        }
    }

    /// The viewport stays open: closing it would leave nothing to edit.
    var canClose: Bool {
        self != .viewport
    }

    /// The smallest size a panel is laid out at.
    var minimumSize: CGSize {
        switch self {
        case .viewport: return CGSize(width: 320, height: 240)
        case .hierarchy: return CGSize(width: 200, height: 160)
        case .inspector: return CGSize(width: 240, height: 160)
        default: return CGSize(width: 240, height: 120)
        }
    }

    /// The area a panel opens in when it has no remembered place; nil for the
    /// viewport, which stays in the centre.
    var defaultArea: DockArea? {
        switch self {
        case .hierarchy: return .left
        case .inspector: return .right
        case .viewport: return nil
        default: return .bottom
        }
    }

    /// Whether a panel can sit in an area at all.
    var isDockable: Bool {
        defaultArea != nil
    }

    /// The panels this build of the editor offers.
    static var available: [PanelID] {
        allCases.filter { $0 != .plugins || EditorFeatureFlags.enableCodeComponents }
    }
}
