//
//  ComponentForm.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import SwiftUI
import UntoldEngine

/// 2) Render fields into controls, wiring refreshView automatically
public struct ComponentForm: View {
    let entityId: EntityID
    let fields: [EditorField]
    let refresh: () -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, field in
                switch field {
                case let .number(label, get, set):
                    TextInputNumberView(
                        label: label,
                        value: Binding(
                            get: { get(entityId) },
                            set: { newValue in set(entityId, newValue); refresh() }
                        )
                    )

                case let .vector3(label, get, set):
                    TextInputVectorView(
                        label: label,
                        value: Binding(
                            get: { get(entityId) },
                            set: { newValue in set(entityId, newValue); refresh() }
                        )
                    )

                case let .text(label, placeholder, get, set):
                    HStack {
                        Text(label)
                            .font(.caption)
                            .foregroundColor(.editorTextSecondary)
                        TextField(placeholder ?? "",
                                  text: Binding(
                                      get: { get(entityId) },
                                      set: { newValue in set(entityId, newValue); refresh() }
                                  ))
                                  .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }
}
