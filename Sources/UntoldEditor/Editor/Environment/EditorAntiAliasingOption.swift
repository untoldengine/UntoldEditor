//
//  EditorAntiAliasingOption.swift
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

enum EditorAntiAliasingOption: String, CaseIterable, Hashable, Identifiable {
    case off = "Off"
    case fxaa = "FXAA"
    case smaa = "SMAA"
    case msaa = "MSAA"

    var id: String {
        rawValue
    }

    var engineMode: AntiAliasingMode {
        switch self {
        case .off:
            return .none
        case .fxaa:
            return .fxaa
        case .smaa:
            return .smaa
        case .msaa:
            return .msaa
        }
    }

    static func currentEngineMode() -> EditorAntiAliasingOption {
        switch antiAliasingMode {
        case .none:
            return .off
        case .fxaa:
            return .fxaa
        case .smaa:
            return .smaa
        case .msaa:
            return .msaa
        }
    }
}
