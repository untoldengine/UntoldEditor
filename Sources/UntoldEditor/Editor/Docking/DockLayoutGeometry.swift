//
//  DockLayoutGeometry.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics
import Foundation

/// The arithmetic of the docking layout: how much of the window each area
/// takes, how far a divider may move, and which area a point over the viewport
/// drops into. Pure functions, so the views stay thin and the rules are testable.
enum DockLayoutGeometry {
    /// The grab area of a divider between an area and the viewport.
    static let dividerThickness: CGFloat = 7
    /// The strip of tabs above an area's content.
    static let tabStripHeight: CGFloat = 34
    /// The row under the tabs that holds the front panel's controls in a side area.
    static let accessoryRowHeight: CGFloat = 30
    /// The strip that stands in for an area with no panels, to drop a tab on.
    static let edgeTargetThickness: CGFloat = 12
    /// The line drawn where a divider will land while it drags.
    static let resizePreviewThickness: CGFloat = 2

    /// The smallest length an area can take: the widest minimum of its tabs for
    /// a side area, the tallest plus the tab strip for the bottom one.
    static func minimumLength(of tabs: [PanelID], in area: DockArea) -> CGFloat {
        guard tabs.isEmpty == false else {
            return 0
        }
        if area.isSide {
            return tabs.map(\.minimumSize.width).max() ?? 0
        }
        return (tabs.map(\.minimumSize.height).max() ?? 0) + tabStripHeight
    }

    /// The widths of the side areas for a window width: what they ask for, no
    /// less than their minimums, shrunk together when the viewport would fall
    /// under its minimum width. Nil is a hidden area.
    static func sideWidths(left: CGFloat?, leftMinimum: CGFloat, right: CGFloat?, rightMinimum: CGFloat, total: CGFloat) -> (left: CGFloat, right: CGFloat) {
        var leftWidth = left.map { max($0, leftMinimum) } ?? 0
        var rightWidth = right.map { max($0, rightMinimum) } ?? 0
        let dividers = (left == nil ? 0 : dividerThickness) + (right == nil ? 0 : dividerThickness)
        let available = max(0, total - dividers - PanelID.viewport.minimumSize.width)
        let asked = leftWidth + rightWidth
        if asked > available, asked > 0 {
            let scale = available / asked
            leftWidth *= scale
            rightWidth *= scale
        }
        return (leftWidth, rightWidth)
    }

    /// The height of the bottom area for a column height: what it asks for, no
    /// less than its minimum, leaving the viewport its minimum height. Nil is a
    /// hidden area.
    static func bottomHeight(_ bottom: CGFloat?, minimum: CGFloat, total: CGFloat) -> CGFloat {
        guard let bottom else {
            return 0
        }
        let available = max(0, total - dividerThickness - PanelID.viewport.minimumSize.height)
        return min(max(bottom, minimum), available)
    }

    /// The most an area may grow to while the viewport keeps its minimum.
    /// `otherSide` is the width the opposite side area takes, zero when hidden.
    static func maximumLength(for area: DockArea, in size: CGSize, otherSide: CGFloat = 0) -> CGFloat {
        if area.isSide {
            let dividers = dividerThickness + (otherSide > 0 ? dividerThickness : 0)
            return max(0, size.width - otherSide - dividers - PanelID.viewport.minimumSize.width)
        }
        return max(0, size.height - dividerThickness - PanelID.viewport.minimumSize.height)
    }

    /// The area a point over the viewport drops into: the left and right quarters
    /// go to the sides, the bottom quarter below; the middle takes nothing.
    static func dropArea(at point: CGPoint, in size: CGSize) -> DockArea? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }
        let x = point.x / size.width
        let y = point.y / size.height
        if x < 0.25 {
            return .left
        }
        if x > 0.75 {
            return .right
        }
        if y > 0.75 {
            return .bottom
        }
        return nil
    }

    /// The strip of the viewport that lights up for an area while a tab drags over it.
    static func viewportDropZoneRect(for area: DockArea, in size: CGSize) -> CGRect {
        switch area {
        case .left:
            return CGRect(x: 0, y: 0, width: size.width * 0.25, height: size.height)
        case .right:
            return CGRect(x: size.width * 0.75, y: 0, width: size.width * 0.25, height: size.height)
        case .bottom:
            return CGRect(x: 0, y: size.height * 0.75, width: size.width, height: size.height * 0.25)
        }
    }

    /// The line for a divider drag, in the container's coordinates: centred in
    /// the grab area the divider would have when `length` is the area's width
    /// or height. `leftSpace` and `rightSpace` are what the side areas take
    /// with their dividers, or their edge strips, so the bottom line spans the
    /// viewport column.
    static func resizePreviewRect(for area: DockArea, length: CGFloat, leftSpace: CGFloat, rightSpace: CGFloat, in size: CGSize) -> CGRect {
        let inset = (dividerThickness - resizePreviewThickness) / 2
        switch area {
        case .left:
            return CGRect(x: length + inset, y: 0, width: resizePreviewThickness, height: size.height)
        case .right:
            return CGRect(x: size.width - length - dividerThickness + inset, y: 0, width: resizePreviewThickness, height: size.height)
        case .bottom:
            return CGRect(x: leftSpace, y: size.height - length - dividerThickness + inset, width: max(0, size.width - leftSpace - rightSpace), height: resizePreviewThickness)
        }
    }
}
