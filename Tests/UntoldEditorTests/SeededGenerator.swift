//
//  SeededGenerator.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

/// Numbers that look random and come out the same on every run, for tests
/// that try many cases and must fail the same way twice.
struct SeededGenerator {
    var state: UInt64

    /// The next number, from `range.lowerBound` up to `range.upperBound`.
    mutating func next(in range: ClosedRange<Float>) -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Float(state >> 40) / Float(1 << 24)
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}
