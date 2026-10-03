//
//  TransformTool.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The tool the viewport header offers for the selection: the gizmo it shows,
/// or none for Select. ⌥1 to ⌥4 pick them; the letters fly the camera.
enum TransformTool: String, CaseIterable, Identifiable {
    case select
    case move
    case rotate
    case scale

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .select: return "Select"
        case .move: return "Move"
        case .rotate: return "Rotate"
        case .scale: return "Scale"
        }
    }

    var systemImage: String {
        switch self {
        case .select: return "square.dashed"
        case .move: return "arrow.up.and.down.and.arrow.left.and.right"
        case .rotate: return "rotate.3d"
        case .scale: return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The shortcut as the tooltip shows it.
    var shortcut: String {
        switch self {
        case .select: return "⌥1"
        case .move: return "⌥2"
        case .rotate: return "⌥3"
        case .scale: return "⌥4"
        }
    }

    /// The macOS virtual key code of the tool's digit, pressed with ⌥.
    var keyCode: UInt16 {
        switch self {
        case .select: return 18
        case .move: return 19
        case .rotate: return 20
        case .scale: return 21
        }
    }

    /// The tool a digit key picks, when pressed with ⌥; nil for any other key.
    static func tool(forKeyCode keyCode: UInt16) -> TransformTool? {
        allCases.first { $0.keyCode == keyCode }
    }

    /// The gizmo the tool shows on the selection; nil for Select.
    var gizmoMode: GizmoMode? {
        switch self {
        case .select: return nil
        case .move: return .translate
        case .rotate: return .rotate
        case .scale: return .scale
        }
    }
}
