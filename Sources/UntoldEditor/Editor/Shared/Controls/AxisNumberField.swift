//
//  AxisNumberField.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import AppKit
import SwiftUI

/// A 24 pt numeric field with a coloured bar for its axis, as the Transform
/// rows use: mono digits, committed on Return or when the field loses focus.
struct AxisNumberField: View {
    let axis: Color
    @Binding var value: Float
    var fractionDigits = 2

    @State private var text = ""

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(axis)
                .frame(width: 2, height: 12)
            CommitAndDefocusTextField(
                text: $text,
                onSubmit: commit,
                font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                isBare: true
            )
        }
        .padding(.horizontal, 6)
        .frame(height: 24)
        .background(Color.editorControlFill)
        .cornerRadius(EditorType.Radius.button)
        .onAppear {
            text = Self.format(value, fractionDigits: fractionDigits)
        }
        .onChange(of: value) { _, newValue in
            text = Self.format(newValue, fractionDigits: fractionDigits)
        }
    }

    private func commit() {
        if let parsed = Self.parse(text) {
            value = parsed
        }
        text = Self.format(value, fractionDigits: fractionDigits)
    }

    static func format(_ value: Float, fractionDigits: Int) -> String {
        String(format: "%.\(fractionDigits)f", value)
    }

    /// A number as typed, with a comma accepted for the decimal point.
    static func parse(_ text: String) -> Float? {
        Float(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }
}
