//
//  DockDragTarget.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics

/// A tab being dragged by the pointer: the panel and where the pointer is, in
/// the dock container's coordinate space.
struct DockTabDrag: Equatable {
    let panel: PanelID
    var location: CGPoint
}

/// Where a dragged tab would dock: the area the pointer is over, or the area
/// an edge of the viewport stands for.
enum DockDragTarget: Equatable {
    case area(DockArea)
    case viewportEdge(DockArea)

    var area: DockArea {
        switch self {
        case let .area(area), let .viewportEdge(area):
            return area
        }
    }
}

/// The frames of the three areas (or of the strips that stand for hidden
/// ones) and of the viewport, in the dock container's coordinate space.
struct DockFrames: Equatable {
    var left = CGRect.zero
    var right = CGRect.zero
    var bottom = CGRect.zero
    var viewport = CGRect.zero
}
