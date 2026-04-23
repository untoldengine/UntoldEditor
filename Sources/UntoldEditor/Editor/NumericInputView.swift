//
//  NumericInputView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
#if canImport(AppKit)
    import AppKit
    import simd
    import SwiftUI

    private struct CommitAndDefocusTextField: NSViewRepresentable {
        @Binding var text: String
        let onSubmit: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text, onSubmit: onSubmit)
        }

        func makeNSView(context: Context) -> NSTextField {
            let textField = ExplicitClickFocusNSTextField(string: text)
            textField.delegate = context.coordinator
            textField.target = context.coordinator
            textField.action = #selector(Coordinator.didSubmitFromAction(_:))
            textField.isBordered = true
            textField.isBezeled = true
            textField.bezelStyle = .roundedBezel
            textField.lineBreakMode = .byClipping
            return textField
        }

        func updateNSView(_ nsView: NSTextField, context: Context) {
            context.coordinator.onSubmit = onSubmit

            if nsView.stringValue != text {
                nsView.stringValue = text
            }
        }

        final class Coordinator: NSObject, NSTextFieldDelegate {
            private let text: Binding<String>
            var onSubmit: () -> Void
            private var suppressNextEndEditingCommit = false

            init(text: Binding<String>, onSubmit: @escaping () -> Void) {
                self.text = text
                self.onSubmit = onSubmit
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let textField = notification.object as? NSTextField else {
                    return
                }

                text.wrappedValue = textField.stringValue
            }

            func controlTextDidEndEditing(_ notification: Notification) {
                if suppressNextEndEditingCommit {
                    suppressNextEndEditingCommit = false
                    return
                }

                onSubmit()
                (notification.object as? ExplicitClickFocusNSTextField)?.clearClickFocus()
            }

            @objc func didSubmitFromAction(_ sender: NSControl) {
                suppressNextEndEditingCommit = true
                onSubmit()
                (sender as? ExplicitClickFocusNSTextField)?.clearClickFocus()
                sender.window?.makeFirstResponder(nil)
            }

            func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                if commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
                    || commandSelector == #selector(NSResponder.insertLineBreak(_:))
                    || commandSelector == #selector(NSResponder.insertTab(_:))
                    || commandSelector == #selector(NSResponder.insertBacktab(_:))
                {
                    suppressNextEndEditingCommit = true
                    onSubmit()
                    (control as? ExplicitClickFocusNSTextField)?.clearClickFocus()
                    control.window?.makeFirstResponder(nil)
                    return true
                }

                return false
            }

        }
    }

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

    public struct CommitAndDefocusIntField: View {
        @Binding var value: Int
        @State private var tempValue = "0"

        public init(value: Binding<Int>) {
            _value = value
        }

        public var body: some View {
            CommitAndDefocusTextField(text: $tempValue, onSubmit: {
                if let parsed = Int(tempValue) {
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

    public struct TextInputNumberView: View {
        let label: String
        @Binding var value: Float
        @State private var tempValues: String = "0"

        public init(label: String, value: Binding<Float>) {
            self.label = label
            _value = value
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
                        tempValues = String(newValue) // Update when entity changes
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
