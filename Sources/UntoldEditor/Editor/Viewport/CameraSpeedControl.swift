//
//  CameraSpeedControl.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The camera speed at the right of the viewport header: a camera glyph and
/// the speed, 1 to 10; a click opens a slider.
struct CameraSpeedControl: View {
    @Binding var speed: Int

    @State private var showSlider = false

    private var sliderValue: Binding<Float> {
        Binding(
            get: { Float(speed) },
            set: { speed = Int($0.rounded()) }
        )
    }

    var body: some View {
        Button {
            showSlider.toggle()
        } label: {
            EditorDropdownLabel("\(speed)") {
                Image(systemName: "video")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Camera speed: how fast the camera flies, orbits and pans")
        .popover(isPresented: $showSlider, arrowEdge: .bottom) {
            EditorPopupMenu(width: 220) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera speed")
                        .font(EditorType.title)
                        .foregroundColor(.editorTextPrimary)
                    HStack(spacing: 8) {
                        EditorSlider(
                            value: sliderValue,
                            range: Float(EditorViewportSettings.speedRange.lowerBound) ... Float(EditorViewportSettings.speedRange.upperBound)
                        )
                        Text("\(speed)")
                            .font(EditorType.mono)
                            .foregroundColor(.editorTextPrimary)
                            .frame(width: 20, alignment: .trailing)
                    }
                }
                .padding(10)
            }
        }
    }
}
