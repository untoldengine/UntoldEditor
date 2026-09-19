//
//  DropStatusToast.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

/// Transient result of an asset drop on the viewport or the hierarchy, in the
/// style of the asset browser's status line.
struct DropStatusToast: View {
    let message: String
    let isError: Bool

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.editorTextPrimary)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(isError ? Color.editorError.opacity(0.85) : Color.editorSuccess.opacity(0.85))
            .cornerRadius(8)
    }
}
