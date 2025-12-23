//
//  EditorScheme.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import SwiftUI

extension Color {
    static let editorBackground = Color(red: 0.15, green: 0.16, blue: 0.21) // dracula background
    static let editorPanelBackground = Color(red: 0.19, green: 0.20, blue: 0.26) // dracula current line
    static let editorSurface = Color(red: 0.24, green: 0.25, blue: 0.32) // dracula selection
    static let editorAccent = Color(red: 0.91, green: 0.64, blue: 0.35) // muted dracula orange
    static let editorAccentSoft = Color(red: 0.91, green: 0.64, blue: 0.35, opacity: 0.16)
    static let editorSecondaryAccent = Color(red: 0.74, green: 0.58, blue: 0.98) // dracula purple
    static let editorDivider = Color.white.opacity(0.10)
}
