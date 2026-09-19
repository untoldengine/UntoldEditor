//
//  CommitAndDefocusFloatField.swift
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

    public struct CommitAndDefocusFloatField: View {
        @Binding var value: Float
        @State private var tempValue = "0"

        public init(value: Binding<Float>) {
            _value = value
        }

        public var body: some View {
            CommitAndDefocusTextField(text: $tempValue, onSubmit: {
                if let parsed = Float(tempValue) {
                    value = parsed
                }
            })
            .onAppear {
                tempValue = String(value)
            }
            .onChange(of: value) { _, newValue in
                tempValue = String(newValue)
            }
        }
    }
#endif
