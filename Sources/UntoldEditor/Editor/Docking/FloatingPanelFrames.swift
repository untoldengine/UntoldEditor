//
//  FloatingPanelFrames.swift
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

/// Where a floating panel's window goes: its remembered frame when enough of
/// it is on a screen to be grabbed, else a default beside the editor window.
/// Pure geometry, in screen points with the origin at the bottom left as
/// AppKit has it.
enum FloatingPanelFrames {
    /// The strip under a window's top edge that holds its title bar.
    static let titleBarHeight: CGFloat = 40
    /// How much of that strip must lie on a screen for the window to be grabbed.
    static let reachableWidth: CGFloat = 120
    static let reachableHeight: CGFloat = 20
    /// Each further window opens this much down and to the left of the last.
    static let cascadeStep: CGFloat = 24
    /// The gap between the editor window's top-right corner and the first window.
    static let inset = CGSize(width: 40, height: 80)

    /// The size a panel's window opens at the first time: tall for the side
    /// panels, wide for the ones from the bottom area, never under the panel's
    /// minimum.
    static func defaultSize(for panel: PanelID) -> CGSize {
        let size = panel.defaultArea == .bottom ? CGSize(width: 640, height: 360) : CGSize(width: 320, height: 560)
        return CGSize(
            width: max(size.width, panel.minimumSize.width),
            height: max(size.height, panel.minimumSize.height)
        )
    }

    /// The frame a panel's window opens at when it has no remembered one: over
    /// the editor window's top-right corner, each further window a step down
    /// and to the left of the one before.
    static func defaultFrame(for panel: PanelID, beside parent: CGRect, index: Int) -> CGRect {
        let size = defaultSize(for: panel)
        let step = cascadeStep * CGFloat(max(index, 0))
        return CGRect(
            x: parent.maxX - size.width - inset.width - step,
            y: parent.maxY - size.height - inset.height - step,
            width: size.width,
            height: size.height
        )
    }

    /// Whether enough of a frame's title bar lies on one of the screens for the
    /// window to be grabbed, so a window remembered on a display that is gone
    /// opens somewhere reachable instead.
    static func isReachable(_ frame: CGRect, on screens: [CGRect]) -> Bool {
        let titleBar = CGRect(x: frame.minX, y: frame.maxY - titleBarHeight, width: frame.width, height: titleBarHeight)
        return screens.contains { screen in
            let visible = screen.intersection(titleBar)
            return visible.width >= reachableWidth && visible.height >= reachableHeight
        }
    }
}
