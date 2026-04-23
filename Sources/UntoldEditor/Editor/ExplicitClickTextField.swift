//
//  ExplicitClickTextField.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
#if canImport(AppKit)
    import AppKit
    import SwiftUI

    final class ExplicitClickFocusNSTextField: NSTextField {
        var allowsFocus = false

        override var acceptsFirstResponder: Bool {
            allowsFocus
        }

        override func mouseDown(with event: NSEvent) {
            allowsFocus = true
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
        }

        func clearClickFocus() {
            allowsFocus = false
        }
    }

    struct ExplicitClickTextField: NSViewRepresentable {
        @Binding var text: String
        let placeholder: String

        func makeCoordinator() -> Coordinator {
            Coordinator(text: $text)
        }

        func makeNSView(context: Context) -> NSTextField {
            let textField = ExplicitClickFocusNSTextField(string: text)
            textField.placeholderString = placeholder
            textField.delegate = context.coordinator
            textField.isBordered = true
            textField.isBezeled = true
            textField.bezelStyle = .roundedBezel
            textField.lineBreakMode = .byClipping
            return textField
        }

        func updateNSView(_ nsView: NSTextField, context _: Context) {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }

            nsView.placeholderString = placeholder
        }

        final class Coordinator: NSObject, NSTextFieldDelegate {
            private let text: Binding<String>

            init(text: Binding<String>) {
                self.text = text
            }

            func controlTextDidChange(_ notification: Notification) {
                guard let textField = notification.object as? NSTextField else {
                    return
                }

                text.wrappedValue = textField.stringValue
            }

            func controlTextDidEndEditing(_ notification: Notification) {
                (notification.object as? ExplicitClickFocusNSTextField)?.clearClickFocus()
            }

            func control(_ control: NSControl, textView _: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
                if commandSelector == #selector(NSResponder.insertNewline(_:))
                    || commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:))
                    || commandSelector == #selector(NSResponder.insertLineBreak(_:))
                    || commandSelector == #selector(NSResponder.insertTab(_:))
                    || commandSelector == #selector(NSResponder.insertBacktab(_:))
                {
                    (control as? ExplicitClickFocusNSTextField)?.clearClickFocus()
                    control.window?.makeFirstResponder(nil)
                    return true
                }

                return false
            }
        }
    }
#endif
