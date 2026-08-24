//
//  LoadingIndicatorView.swift
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

/// SwiftUI view that displays asset loading progress
public struct LoadingIndicatorView: View {
    @State private var isLoading = false
    @State private var loadingSummary = "Loading..."
    @State private var currentProgress: Float = 0.0
    @State private var totalCount = 0

    /// Timer to poll loading state
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    public init() {}

    public var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 0) {
                    Spacer()

                    HStack {
                        Spacer()

                        VStack(spacing: 12) {
                            // Progress spinner
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                                .scaleEffect(0.8)

                            // Loading text
                            Text(loadingSummary)
                                .font(.system(size: 12))
                                .foregroundColor(.editorTextPrimary)

                            // Progress bar if we have total count
                            if totalCount > 0 {
                                ProgressView(value: currentProgress, total: 1.0)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .frame(width: 200)

                                Text("\(Int(currentProgress * 100))%")
                                    .font(.system(size: 10))
                                    .foregroundColor(.editorTextSecondary)
                            }
                        }
                        .padding(16)
                        .background(Color.editorOverlay)
                        .cornerRadius(8)
                        .shadow(radius: 10)

                        Spacer()
                    }

                    Spacer()
                        .frame(height: 80) // Position slightly above bottom
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: isLoading)
            }
        }
        .onReceive(timer) { _ in
            updateLoadingState()
        }
    }

    private func updateLoadingState() {
        Task {
            let loading = await AssetLoadingState.shared.isLoadingAny()
            let summary = await AssetLoadingState.shared.loadingSummary()
            let (current, total) = await AssetLoadingState.shared.totalProgress()

            await MainActor.run {
                isLoading = loading
                loadingSummary = summary
                totalCount = total

                if total > 0 {
                    currentProgress = Float(current) / Float(total)
                } else {
                    currentProgress = 0.0
                }
            }
        }
    }
}

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
