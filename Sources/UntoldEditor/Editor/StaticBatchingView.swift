//
//  StaticBatchingView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
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
                    .foregroundColor(.primary)
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
                    .foregroundColor(.secondary)
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
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                        Text("Generate Batches")
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
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
                            .foregroundColor(.white)
                            .font(.system(size: 12))
                        Text("Clear Batches")
                            .font(.system(size: 12))
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color.red.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Success message
            if showGenerateSuccess {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Batches generated successfully!")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                .padding(6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
                .transition(.opacity)
            }

            Divider()

            // MARK: - Info Section

            VStack(alignment: .leading, spacing: 6) {
                Text("Batch Statistics")
                    .font(.system(size: 12))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                HStack {
                    Text("Active Batches:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(batchCount)")
                        .font(.system(size: 11))
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
            }
            .padding(.vertical, 4)

            Divider()

            // MARK: - Help Section

            VStack(alignment: .leading, spacing: 4) {
                Text("How to use:")
                    .font(.system(size: 11))
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("1. Mark entities as static in Inspector")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("2. Enable batching toggle above")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("3. Click 'Generate Batches'")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text("Note: Moving a static entity will automatically disable its batching.")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
                    .padding(.top, 4)
            }
            .padding(.vertical, 4)

            Spacer()
        }
        .padding(8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
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
