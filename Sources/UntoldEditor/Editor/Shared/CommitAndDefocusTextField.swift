//
//  CommitAndDefocusTextField.swift
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

    struct CommitAndDefocusTextField: NSViewRepresentable {
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
#endif
