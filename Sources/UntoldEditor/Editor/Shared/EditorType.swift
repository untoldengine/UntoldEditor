//
//  EditorType.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The editor's type scale and corner radii, from the redesign spec: the system
/// font throughout, small sizes, monospaced digits wherever a value is read.
enum EditorType {
    /// Body text and control labels.
    static let body = Font.system(size: 12)
    /// Panel titles, active tab labels, menu row titles.
    static let title = Font.system(size: 12, weight: .semibold)
    /// Toolbar labels, such as the project name.
    static let toolbar = Font.system(size: 13, weight: .semibold)
    /// Hints, footers, chips and subtitles.
    static let hint = Font.system(size: 11)
    /// Badges such as the viewport mode badge.
    static let badge = Font.system(size: 11, weight: .semibold)
    /// Numeric values, shortcuts, timecodes and console rows.
    static let mono = Font.system(size: 11, design: .monospaced)
    /// Dense numeric labels such as a ruler.
    static let monoSmall = Font.system(size: 10, design: .monospaced)

    /// Corner radii: fields and dropdowns, grouped pills, the buttons inside a
    /// pill, and cards or popovers.
    enum Radius {
        static let field: CGFloat = 6
        static let pill: CGFloat = 7
        static let button: CGFloat = 5
        static let card: CGFloat = 8
    }
}
