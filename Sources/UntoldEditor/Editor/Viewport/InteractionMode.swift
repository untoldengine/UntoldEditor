//
//  InteractionMode.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// How the viewport is used. Object mode places objects and edits their
/// properties; the other modes of the design wait for their engine features
/// and are not listed until then.
enum InteractionMode: String, CaseIterable, Identifiable {
    case object

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .object: return "Object Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .object: return "Select & place entities"
        }
    }

    var dotColor: Color {
        switch self {
        case .object: return .editorModeObject
        }
    }
}
