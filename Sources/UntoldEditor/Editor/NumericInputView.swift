//
//  NumericInputView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
#if canImport(AppKit)
    import simd
    import SwiftUI

    public struct TextInputVectorView: View {
        let label: String
        @Binding var value: SIMD3<Float>
        @State private var tempValues: [String] = ["0", "0", "0"]
        @FocusState private var focusedField: Int?

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
                        TextField("", text: Binding(
                            get: { tempValues[index] },
                            set: { tempValues[index] = $0 }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 60)
                        .focused($focusedField, equals: index)
                        .onChange(of: value[index]) { _, newValue in
                            tempValues[index] = String(newValue) // Update when entity changes
                        }
                        .onSubmit {
                            if let newValue = Float(tempValues[index]) {
                                value[index] = newValue
                            }
                            focusedField = nil
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

    public struct TextInputNumberView: View {
        let label: String
        @Binding var value: Float
        @State private var tempValues: String = "0"
        @FocusState private var focusedField: Int?

        public init(label: String, value: Binding<Float>) {
            self.label = label
            _value = value
        }

        public var body: some View {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.headline)

                HStack {
                    TextField("", text: Binding(
                        get: { tempValues },
                        set: { tempValues = $0 }
                    ))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 60)
                    .focused($focusedField, equals: 1)
                    .onChange(of: value) { _, newValue in
                        tempValues = String(newValue) // Update when entity changes
                    }
                    .onSubmit {
                        if let newValue = Float(tempValues) {
                            value = newValue
                        }
                        focusedField = nil
                    }
                }
            }
            .padding(.vertical, 4)
            .onAppear {
                tempValues = String(value)
            }
        }
    }
#endif
