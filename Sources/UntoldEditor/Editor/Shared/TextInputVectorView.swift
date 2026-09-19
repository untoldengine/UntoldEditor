//
//  TextInputVectorView.swift
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

    public struct TextInputVectorView: View {
        let label: String
        @Binding var value: SIMD3<Float>
        @State private var tempValues: [String] = ["0", "0", "0"]

        public init(label: String, value: Binding<SIMD3<Float>>) {
            self.label = label
            _value = value
        }

        public var body: some View {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.headline)

                HStack {
                    ForEach(0 ..< 3, id: \.self) { index in
                        CommitAndDefocusTextField(text: Binding(
                            get: { tempValues[index] },
                            set: { tempValues[index] = $0 }
                        ), onSubmit: {
                            if let newValue = Float(tempValues[index]) {
                                value[index] = newValue
                            }
                        })
                        .frame(width: 60)
                        .onChange(of: value[index]) { _, newValue in
                            tempValues[index] = String(newValue) // Update when entity changes
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                tempValues = [String(value.x), String(value.y), String(value.z)] // Convert explicitly
            }
        }
    }
#endif
