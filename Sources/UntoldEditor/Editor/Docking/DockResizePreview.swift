//
//  DockResizePreview.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics

/// A divider drag in progress: the area it resizes and the length the area
/// would take if the mouse went up now. The layout does not change until it does.
struct DockResizePreview: Equatable {
    let area: DockArea
    var length: CGFloat
}
