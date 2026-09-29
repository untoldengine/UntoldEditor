//
//  ViewportToolCluster.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Select, Move, Rotate and Scale, side by side.
struct ViewportToolCluster: View {
    let tool: TransformTool
    let onSelect: (TransformTool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(TransformTool.allCases) { candidate in
                ViewportToolButton(tool: candidate, isActive: candidate == tool) {
                    onSelect(candidate)
                }
            }
        }
    }
}
