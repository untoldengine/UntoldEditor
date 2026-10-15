//
//  EditorTonemapOption.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CShaderTypes
import simd
import SwiftUI
import UntoldEngine

enum EditorTonemapOption: String, CaseIterable, Hashable, Identifiable {
    case agx = "AgX"
    case aces = "ACES"
    /// No curve: the scene's linear colour as it is, for a mixed-immersion space where the
    /// passthrough sets the display's response.
    case none = "None"

    var id: String {
        rawValue
    }

    var engineOperator: TonemapOperator {
        switch self {
        case .agx:
            return .agx
        case .aces:
            return .aces
        case .none:
            return .none
        }
    }

    static func currentEngineOperator() -> EditorTonemapOption {
        switch TonemapParams.shared.operator {
        case .agx:
            return .agx
        case .aces:
            return .aces
        case .none:
            return .none
        }
    }
}
