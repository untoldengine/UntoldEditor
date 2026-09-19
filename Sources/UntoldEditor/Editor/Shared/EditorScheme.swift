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

// MARK: - Editor color scheme (Dracula-inspired)

///
/// Single source of truth for the editor UI palette. All views should reference
/// these semantic tokens instead of hardcoding `Color.white`, `.secondary`,
/// `.red`, opacities, etc. Grouped by role so a re-theme only touches this file.
extension Color {
    // MARK: Base surfaces

    static let editorBackground = Color(red: 0.15, green: 0.16, blue: 0.21) // dracula background
    static let editorPanelBackground = Color(red: 0.19, green: 0.20, blue: 0.26) // dracula current line
    static let editorSurface = Color(red: 0.24, green: 0.25, blue: 0.32) // dracula selection

    // MARK: Accents

    static let editorAccent = Color(red: 0.91, green: 0.64, blue: 0.35) // muted dracula orange
    static let editorAccentSoft = Color(red: 0.91, green: 0.64, blue: 0.35, opacity: 0.16)
    static let editorSecondaryAccent = Color(red: 0.74, green: 0.58, blue: 0.98) // dracula purple

    // MARK: Text hierarchy

    static let editorTextPrimary = Color.white // titles, primary labels, text on accent buttons
    static let editorTextSecondary = Color.white.opacity(0.70) // supporting / secondary labels
    static let editorTextTertiary = Color.white.opacity(0.45) // muted / disabled-looking labels
    static let editorTextInverse = Color.black.opacity(0.90) // dark text on light/accent fills

    // MARK: Semantic status

    static let editorError = Color(red: 0.94, green: 0.38, blue: 0.42) // dracula red
    static let editorSuccess = Color(red: 0.31, green: 0.82, blue: 0.55) // dracula green
    static let editorWarning = Color(red: 0.95, green: 0.78, blue: 0.42) // dracula yellow/orange
    static let editorInfo = Color(red: 0.55, green: 0.73, blue: 0.98) // dracula blue/cyan

    // MARK: Fills & separators

    static let editorFillSubtle = Color.white.opacity(0.05) // faint row / zebra backgrounds
    static let editorFill = Color.white.opacity(0.10) // subtle panel / hover fills
    static let editorDivider = Color.white.opacity(0.10) // borders, strokes, separators
    static let editorDisabled = Color.white.opacity(0.15) // disabled control backgrounds

    // MARK: Overlays & shadows

    static let editorShadow = Color.black.opacity(0.20) // default drop shadows
    static let editorShadowStrong = Color.black.opacity(0.34) // elevated cards / popovers
    static let editorScrim = Color.black.opacity(0.40) // floating stat cards over the scene
    static let editorBadgeBackground = Color.black.opacity(0.18) // small badges / pills
    static let editorOverlay = Color.black.opacity(0.70) // full-screen dimming overlays
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

/// Disclosure style where each nesting level is indented by exactly the width of
/// the expand/collapse chevron, so a child's content lines up with its parent's
/// label text. Also themes the chevron to match the editor.
struct EditorDisclosureStyle: DisclosureGroupStyle {
    private let chevronWidth: CGFloat = 12
    private let spacing: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: spacing) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.editorTextSecondary)
                        .frame(width: chevronWidth)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, chevronWidth + spacing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
