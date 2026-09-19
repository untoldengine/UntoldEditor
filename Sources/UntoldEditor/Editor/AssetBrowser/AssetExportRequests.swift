//
//  AssetExportRequests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

struct RuntimeExportRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    let category: AssetCategory
    let destinationFolder: URL
    let outputURL: URL
}

struct TilesExportRequest: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    let destinationFolder: URL
    let outputDirURL: URL
}
