//
//  EntityRowToggle.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The eye or the lock at the end of a hierarchy row.
struct EntityRowToggle: View {
    let systemImage: String
    let tint: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10))
                .foregroundColor(tint)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}
