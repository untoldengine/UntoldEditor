//
//  NavigationDrag.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import CoreGraphics
import simd

/// A press on a navigation control of the viewport, followed from the
/// distances a drag gesture reports: how far the pointer is from where it
/// went down. It tells a click from a drag and hands out the drag in steps.
struct NavigationDrag {
    /// How far the pointer travels before the press is a drag and not a click.
    let clickSlop: CGFloat
    /// The shortest step handed out. The pointer's travel is kept until it
    /// adds up to one, so a slow drag loses nothing.
    let minimumStep: CGFloat

    /// True once the press travelled beyond the click slop.
    private(set) var isDragging = false
    private var applied = CGSize.zero

    init(clickSlop: CGFloat = 3, minimumStep: CGFloat = 0) {
        self.clickSlop = clickSlop
        self.minimumStep = minimumStep
    }

    /// The step since the last one handed out, in points with x to the right
    /// and y up the screen; nil while the press is still a click, and while
    /// the travel since the last step is shorter than the minimum.
    mutating func step(to translation: CGSize) -> simd_float2? {
        if isDragging == false {
            guard hypot(translation.width, translation.height) > clickSlop else {
                return nil
            }
            isDragging = true
        }

        let travel = CGSize(width: translation.width - applied.width, height: translation.height - applied.height)
        guard travel != .zero, hypot(travel.width, travel.height) >= minimumStep else {
            return nil
        }
        applied = translation
        // The gesture's y grows down the screen.
        return simd_float2(Float(travel.width), Float(-travel.height))
    }
}
