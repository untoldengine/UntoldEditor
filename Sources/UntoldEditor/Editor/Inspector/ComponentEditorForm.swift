//
//  ComponentEditorForm.swift
//
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

/// 1) Describe the fields you want to render
public enum EditorField {
    case number(label: String,
                get: (EntityID) -> Float,
                set: (EntityID, Float) -> Void)

    case vector3(label: String,
                 get: (EntityID) -> SIMD3<Float>,
                 set: (EntityID, SIMD3<Float>) -> Void)

    case text(label: String,
              placeholder: String?,
              get: (EntityID) -> String,
              set: (EntityID, String) -> Void)
}

/// 3) Helper to produce the `view:` closure you already use
public func makeEditorView(fields: [EditorField]) -> (EntityID?, Asset?, @escaping () -> Void) -> AnyView {
    { selectedId, _, refresh in
        AnyView(
            VStack(alignment: .leading, spacing: 12) {
                if let id = selectedId {
                    ComponentForm(entityId: id, fields: fields, refresh: refresh)
                }
            }
        )
    }
}
