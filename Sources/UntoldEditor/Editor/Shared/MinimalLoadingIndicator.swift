//
//  MinimalLoadingIndicator.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UntoldEngine

/// Minimal loading indicator for small operations
public struct MinimalLoadingIndicator: View {
    @State private var isLoading = false
    private let timer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(0.5)

                    Text("Loading...")
                        .font(.system(size: 10))
                        .foregroundColor(.editorTextSecondary)
                }
                .padding(6)
                .background(Color.editorOverlay)
                .cornerRadius(4)
            }
        }
        .onReceive(timer) { _ in
            updateState()
        }
    }

    private func updateState() {
        Task {
            let loading = await AssetLoadingState.shared.isLoadingAny()
            await MainActor.run {
                isLoading = loading
            }
        }
    }
}

#Preview {
    ZStack {
        Color.editorBackground.ignoresSafeArea()
        LoadingIndicatorView()
    }
}
