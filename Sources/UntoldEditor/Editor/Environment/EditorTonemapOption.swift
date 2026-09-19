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

    var id: String {
        rawValue
    }

    var engineOperator: TonemapOperator {
        switch self {
        case .agx:
            return .agx
        case .aces:
            return .aces
        }
    }

    static func currentEngineOperator() -> EditorTonemapOption {
        switch TonemapParams.shared.operator {
        case .agx:
            return .agx
        case .aces:
            return .aces
        }
    }
}
