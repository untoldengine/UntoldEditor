//
//  EditorScheme.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

// MARK: - Editor color scheme

/// Single source of truth for the editor UI palette. All views should reference
/// these semantic tokens instead of hardcoding `Color.white`, `.secondary`,
/// `.red`, opacities, etc. Grouped by role so a re-theme only touches this file.
///
/// The values come from the editor redesign mockups (the engine repository's
/// `docs/proposals/EditorUIRedesign`): neutral dark chrome, one orange accent that
/// always means "selected" or "active", never a plain action button.
extension Color {
    // MARK: Base surfaces

    static let editorBackground = Color(hex: 0x2A2C35) // window body, bottom dock
    static let editorPanelBackground = Color(hex: 0x2E3039) // side panels
    static let editorSurface = Color(hex: 0x3F414D) // raised surfaces, active segments
    static let editorChromeBackground = Color(hex: 0x30323D) // main toolbar
    static let editorViewportHeader = Color(hex: 0x2E3039) // viewport tool header
    static let editorTabStrip = Color(hex: 0x242630) // scene tab strip
    static let editorBarDark = Color(hex: 0x1F2028) // status bar

    // MARK: Controls

    static let editorControlFill = Color.black.opacity(0.28) // pills, fields, menus
    static let editorControlActive = Color(hex: 0x3F414D) // active segment or tab
    static let editorHairline = Color.black.opacity(0.40) // toolbar and section hairlines

    // MARK: Accents

    static let editorAccent = Color(hex: 0xF39C3D) // orange: selection and active state
    static let editorAccentSoft = Color(hex: 0xF39C3D, opacity: 0.22) // selected rows and cells
    static let editorSecondaryAccent = Color(hex: 0x4F8DE0) // blue: secondary emphasis

    // MARK: Text hierarchy

    static let editorTextPrimary = Color(hex: 0xE6E7EC) // titles, primary labels
    static let editorTextSecondary = Color(hex: 0xC8CAD2) // supporting labels
    static let editorTextTertiary = Color(hex: 0x8A8C97) // muted labels, hints
    static let editorTextDisabled = Color(hex: 0x5F616C) // disabled controls, hidden rows
    static let editorTextInverse = Color(hex: 0x1F2028) // dark text on accent fills
    static let editorTextSelected = Color(hex: 0xFFD9AD) // text of a selected hierarchy row

    // MARK: Semantic status

    static let editorError = Color(hex: 0xFF7B7B)
    static let editorSuccess = Color(hex: 0x5CE08C)
    static let editorWarning = Color(hex: 0xF5C451)
    static let editorInfo = Color(hex: 0x4F8DE0)
    static let editorErrorText = Color(hex: 0xFFB3B3) // console error rows
    static let editorWarningText = Color(hex: 0xF0D9A0) // console warning rows
    static let editorErrorRowBackground = Color(hex: 0xE5484D, opacity: 0.12)
    static let editorBadge = Color(hex: 0xE5484D) // unread-error badge

    // MARK: Axes and navigation gizmo

    static let editorAxisX = Color(hex: 0xFF5A5A)
    static let editorAxisY = Color(hex: 0x5CE08C)
    static let editorAxisZ = Color(hex: 0x4C8DFF)
    static let editorNavX = Color(hex: 0xE0574F)
    static let editorNavY = Color(hex: 0x8BC34A)
    static let editorNavZ = Color(hex: 0x4F8DE0)

    // MARK: Interaction modes

    static let editorModeObject = Color(hex: 0xE6E7EC)
    static let editorModeEdit = Color(hex: 0xF39C3D)
    static let editorModeAnimate = Color(hex: 0x4F8DE0)
    static let editorModePaint = Color(hex: 0xB53F7A)

    // MARK: Fills & separators

    static let editorFillSubtle = Color.white.opacity(0.05) // faint row / zebra backgrounds
    static let editorFill = Color.white.opacity(0.10) // subtle panel / hover fills
    static let editorDivider = Color.white.opacity(0.10) // borders, strokes, separators
    static let editorDisabled = Color.white.opacity(0.15) // disabled control backgrounds

    // MARK: Overlays & shadows

    static let editorShadow = Color.black.opacity(0.20) // default drop shadows
    static let editorShadowStrong = Color.black.opacity(0.50) // popovers
    static let editorScrim = Color(hex: 0x14151C, opacity: 0.55) // floating cards over the scene
    static let editorBadgeBackground = Color.black.opacity(0.25) // small badges / pills
    static let editorOverlay = Color.black.opacity(0.70) // full-screen dimming overlays
}

private extension Color {
    /// A color from a `0xRRGGBB` literal, the form the design spec uses.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// Standard editor panel card: subtle fill, rounded corners and a soft
    /// shadow. Used to give right-panel editors (Environment, Effects,
    /// Inspector) a consistent look. Inner content sits 5pt from every edge.
    func editorPanel() -> some View {
        padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.editorFillSubtle)
            .cornerRadius(8)
            .shadow(color: Color.editorShadow, radius: 3, x: 0, y: 1)
    }
}
