//
//  EngineStatsOverlayMode.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import SwiftUI
import UntoldEngine

/// The form of the frame statistics over the viewport: none, the two compact
/// lines, or every number the engine reports.
enum EngineStatsOverlayMode: String {
    case off
    case simplified
    case advanced
}
