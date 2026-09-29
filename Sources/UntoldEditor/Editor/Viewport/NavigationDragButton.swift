//
//  NavigationDragButton.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// A round button under the navigation gizmo that is dragged, not clicked:
/// press it and move the pointer to zoom or to pan, for a trackpad or a mouse
/// with one button. It lights up while it is held.
struct NavigationDragButton: View {
    static let size: CGFloat = 26

    let systemImage: String
    let help: String
    let handlers: NavigationDragHandlers

    @State private var drag: NavigationDrag?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(drag == nil ? Color.editorTextPrimary : Color.editorAccent)
            .frame(width: Self.size, height: Self.size)
            .background(Color.editorScrim)
            .clipShape(Circle())
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if drag == nil {
                            // Any travel counts: there is no click to tell it from.
                            drag = NavigationDrag(clickSlop: 0)
                            handlers.began()
                        }
                        if let step = drag?.step(to: value.translation) {
                            handlers.moved(step)
                        }
                    }
                    .onEnded { _ in
                        drag = nil
                        handlers.ended()
                    }
            )
            .help(help)
            .accessibilityLabel(help)
    }
}
