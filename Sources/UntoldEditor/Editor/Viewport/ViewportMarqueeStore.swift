//
//  ViewportMarqueeStore.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import CoreGraphics

/// The rectangle being dragged over the viewport to select what is inside it.
/// The canvas writes it while the left button is dragged, and the viewport
/// draws it.
final class ViewportMarqueeStore: ObservableObject {
    static let shared = ViewportMarqueeStore()

    /// The rectangle in points from the top left of the viewport, as the
    /// view that draws it measures; nil while none is dragged.
    @Published private(set) var rect: CGRect?

    init() {}

    func show(_ rect: CGRect) {
        if self.rect != rect {
            self.rect = rect
        }
    }

    func hide() {
        if rect != nil {
            rect = nil
        }
    }
}
