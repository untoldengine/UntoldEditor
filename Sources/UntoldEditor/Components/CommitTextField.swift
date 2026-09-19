//
//  CommitTextField.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import simd
import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// A text field that reports on Return or when it loses focus, not on every keystroke.
struct CommitTextField: View {
    let text: String
    let multiline: Bool
    let onCommit: (String) -> Void

    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if multiline {
                TextField("", text: $draft, axis: .vertical).lineLimit(2 ... 6)
            } else {
                TextField("", text: $draft)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.caption)
        .focused($isFocused)
        .onAppear { draft = text }
        .onChange(of: text) { _, newValue in
            if isFocused == false {
                draft = newValue
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused == false {
                onCommit(draft)
            }
        }
        .onSubmit { onCommit(draft) }
    }
}
