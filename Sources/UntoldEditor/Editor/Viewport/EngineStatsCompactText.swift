//
//  EngineStatsCompactText.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// The two lines of the compact frame statistics: the frame rate with the
/// frame's time, and what was drawn. Pure functions, so the formatting is
/// tested without a running engine.
enum EngineStatsCompactText {
    /// "62 fps · 4.2 ms", or dashes while the engine reports no frame.
    static func timing(frameMs: Double) -> String {
        guard frameMs > 0, frameMs.isFinite else {
            return "— fps · — ms"
        }
        return "\(Int((1000 / frameMs).rounded())) fps · \(String(format: "%.1f", frameMs)) ms"
    }

    /// "1,248 tris · 3 draw calls".
    static func drawn(triangles: Int, drawCalls: Int) -> String {
        let count = grouped.string(from: NSNumber(value: triangles)) ?? "\(triangles)"
        return "\(count) \(triangles == 1 ? "tri" : "tris") · \(EditorStatusModel.drawCalls(drawCalls))"
    }

    /// Thousands in groups, the same in every region so the numbers read as the docs show them.
    private static let grouped: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}
