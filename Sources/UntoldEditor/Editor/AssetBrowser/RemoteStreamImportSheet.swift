//
//  RemoteStreamImportSheet.swift
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

struct RemoteStreamImportSheet: View {
    @Binding var urlString: String
    var onImport: () -> Void
    var onCancel: () -> Void

    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Remote Stream")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Manifest URL")
                    .font(.system(size: 12))
                    .foregroundColor(.editorTextSecondary)
                TextField("https://cdn.example.com/dungeon/dungeon.json", text: $urlString)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isURLFocused)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                Button("Import", action: onImport)
                    .disabled(urlString.trimmingCharacters(in: .whitespaces).isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear { isURLFocused = true }
    }
}
