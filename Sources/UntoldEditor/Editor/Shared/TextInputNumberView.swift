//
//  TextInputNumberView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

#if canImport(AppKit)
    import AppKit
    import simd
    import SwiftUI

    public struct TextInputNumberView: View {
        let label: String
        @Binding var value: Float
        /// When set, displayed values are rounded to this many decimal places
        /// (e.g. to keep long floats from overflowing the field's fixed width).
        /// Editing still accepts full-precision input.
        let fractionDigits: Int?
        @State private var tempValues: String = "0"

        public init(label: String, value: Binding<Float>, fractionDigits: Int? = nil) {
            self.label = label
            _value = value
            self.fractionDigits = fractionDigits
        }

        private func displayString(for value: Float) -> String {
            guard let fractionDigits else { return String(value) }
            return String(format: "%.\(fractionDigits)f", value)
        }

        public var body: some View {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.headline)

                HStack {
                    CommitAndDefocusTextField(text: Binding(
                        get: { tempValues },
                        set: { tempValues = $0 }
                    ), onSubmit: {
                        if let newValue = Float(tempValues) {
                            value = newValue
                        }
                    })
                    .frame(width: 60)
                    .onChange(of: value) { _, newValue in
                        tempValues = displayString(for: newValue) // Update when entity changes
                    }
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                tempValues = displayString(for: value)
            }
        }
    }
#endif
