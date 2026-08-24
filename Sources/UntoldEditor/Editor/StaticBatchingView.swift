//
//  StaticBatchingView.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

@available(macOS 12.0, *)
struct StaticBatchingView: View {
    @State private var isBatchingEnabled: Bool = false
    @State private var batchCount: Int = 0
    @State private var showGenerateSuccess: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Header

            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                Text("Static Batching")
                    .font(.headline)
                    .foregroundColor(.editorTextPrimary)
            }
            .padding(.bottom, 6)

            Divider()

            // MARK: - Enable Batching Toggle

            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $isBatchingEnabled) {
                    Label("Enable Batching", systemImage: isBatchingEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 12))
                }
                .toggleStyle(SwitchToggleStyle())
                .scaleEffect(0.85)
                .onChange(of: isBatchingEnabled) { _, newValue in
                    enableBatching(newValue)
                }

                Text("Enable the batching system globally")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)
            }

            Divider()

            // MARK: - Action Buttons

            VStack(spacing: 8) {
                // Generate Batches Button
                Button(action: {
                    generateBatches()
                    updateBatchCount()
                    showGenerateSuccess = true

                    // Hide success message after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        showGenerateSuccess = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .foregroundColor(.editorTextPrimary)
                            .font(.system(size: 12))
                        Text("Generate Batches")
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.editorInfo)
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isBatchingEnabled)

                // Clear Batches Button
                Button(action: {
                    clearSceneBatches()
                    updateBatchCount()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.editorTextPrimary)
                            .font(.system(size: 12))
                        Text("Clear Batches")
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.editorError.opacity(0.8))
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Success message
            if showGenerateSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.editorSuccess)
                    Text("Batches generated successfully!")
                        .font(.system(size: 11))
                        .foregroundColor(.editorSuccess)
                }
                .padding(6)
                .background(Color.editorSuccess.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity)
            }

            Divider()

            // MARK: - Info Section

            VStack(alignment: .leading, spacing: 6) {
                Text("Batch Statistics")
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(.editorTextPrimary)

                HStack {
                    Text("Active Batches:")
                        .font(.system(size: 11))
                        .foregroundColor(.editorTextSecondary)
                    Spacer()
                    Text("\(batchCount)")
                        .font(.system(size: 11))
                        .fontWeight(.medium)
                        .foregroundColor(.editorTextPrimary)
                }
            }
            .padding(.vertical, 4)

            Divider()

            // MARK: - Help Section

            VStack(alignment: .leading, spacing: 4) {
                Text("How to use:")
                    .font(.system(size: 11))
                    .fontWeight(.semibold)
                    .foregroundColor(.editorTextPrimary)

                Text("1. Mark entities as static in Inspector")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)

                Text("2. Enable batching toggle above")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)

                Text("3. Click 'Generate Batches'")
                    .font(.system(size: 10))
                    .foregroundColor(.editorTextSecondary)

                Text("Note: Moving a static entity will automatically disable its batching.")
                    .font(.system(size: 9))
                    .foregroundColor(.editorWarning)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)

            Spacer()
        }
        .padding(8)
        .background(Color.editorFill)
        .cornerRadius(8)
        .shadow(color: Color.editorShadow, radius: 3, x: 0, y: 1)
        .onAppear {
            isBatchingEnabled = UntoldEngine.isBatchingEnabled()
            updateBatchCount()
        }
    }

    private func updateBatchCount() {
        // Get batch count from BatchingSystem
        batchCount = BatchingSystem.shared.batchGroups.count
    }
}
