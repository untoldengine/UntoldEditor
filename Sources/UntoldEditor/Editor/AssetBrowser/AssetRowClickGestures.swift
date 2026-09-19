//
//  AssetRowClickGestures.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

/// Click handling for a content browser row. A file row selects on the very
/// first click: its double-click is a simultaneous gesture, so SwiftUI does not
/// hold the single click back until the double-click interval has passed (the
/// sequential `onTapGesture(count: 2)` then `onTapGesture(count: 1)` pair does,
/// which reads as a laggy selection). On a double-click the row is selected
/// twice, harmlessly, and then placed. A folder row keeps the sequential pair:
/// its single click navigates into the folder, which would otherwise fire
/// before the double-click that places the folder's primary asset.
struct AssetRowClickGestures: ViewModifier {
    let isFolder: Bool
    let onClick: () -> Void
    let onDoubleClick: () -> Void

    func body(content: Content) -> some View {
        if isFolder {
            content
                .onTapGesture(count: 2, perform: onDoubleClick)
                .onTapGesture(count: 1, perform: onClick)
        } else {
            content
                .onTapGesture(perform: onClick)
                .simultaneousGesture(TapGesture(count: 2).onEnded(onDoubleClick))
        }
    }
}
