//
//  ModeBadgeView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The interaction mode at the top left of the viewport, in capitals. Object
/// mode is a dark scrim; a mode that changes what a click does takes its own
/// colour, so it cannot be missed. Clicks go through it to the scene.
struct ModeBadgeView: View {
    let mode: InteractionMode

    var body: some View {
        Text(mode.title.uppercased())
            .font(EditorType.badge)
            .foregroundColor(Self.textColor(for: mode))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Self.background(for: mode))
            .cornerRadius(EditorType.Radius.button)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityLabel(mode.title)
    }

    static func background(for mode: InteractionMode) -> Color {
        switch mode {
        case .object: return .editorScrim
        }
    }

    static func textColor(for mode: InteractionMode) -> Color {
        switch mode {
        case .object: return .editorTextPrimary
        }
    }
}
