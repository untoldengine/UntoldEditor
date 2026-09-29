//
//  TransformSpace.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The axes the gizmo works along: the world's, or the entity's own.
enum TransformSpace: String, CaseIterable, Identifiable {
    case world
    case local

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .world: return "World"
        case .local: return "Local"
        }
    }

    var help: String {
        switch self {
        case .world: return "Move, rotate and scale along the world's axes"
        case .local: return "Move, rotate and scale along the entity's own axes"
        }
    }
}
