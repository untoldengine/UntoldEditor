//
//  GaussianTwinInspectorView.swift
//  UntoldEditor
//
//  The Inspector's "Splat Twin" section: links a mesh placed from a `.untold` asset to the
//  cooked `.untoldgs` that stands in for it up close. The link is stored in the `.untold`
//  file (its `gaussianAsset` record), so every app that loads the asset and runs
//  `GaussianTwinSystem` gets the swap; the viewport previews it while View > Preview Splat
//  Twins is on.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

/// An open panel limited to cooked `.untoldgs` payloads.
private func pickGaussianPayloadFile() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowedContentTypes = [UTType(filenameExtension: "untoldgs")].compactMap { $0 }
    panel.message = "Choose the cooked .untoldgs splat that stands in for this mesh"

    return panel.runModal() == .OK ? panel.urls.first : nil
}

/// Rendered from `InspectorView.body` when `GaussianTwinInspector.isAvailable` says so;
/// identified by the entity so a new selection gets a fresh model.
struct GaussianTwinInspectorView: View {
    @StateObject private var model: GaussianTwinInspectorModel
    @ObservedObject private var preview = GaussianTwinPreviewSettings.shared
    /// Observed so the Align Mode checkbox (`model.isAlignMode` reads it) follows a mode ended
    /// elsewhere: scene reset, preview off, the link undone away.
    @ObservedObject private var alignMode = GaussianTwinAlignMode.shared
    @State private var liveState: String?
    let asset: Asset?
    let refreshView: () -> Void

    private let stateTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    init(entityId: EntityID, asset: Asset?, refreshView: @escaping () -> Void) {
        _model = StateObject(wrappedValue: GaussianTwinInspectorModel(entityId: entityId))
        self.asset = asset
        self.refreshView = refreshView
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundColor(.editorTextSecondary)
                Text("Splat Twin")
                    .font(.headline)
                Spacer()
            }

            Text(model.payloadDisplay)
                .font(.caption)
                .foregroundColor(model.link == nil ? .editorTextTertiary : .editorTextSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .help(model.payloadURL?.path ?? "Assign a cooked .untoldgs to swap this mesh for its splat twin.")

            HStack(spacing: 6) {
                Button("Assign Selected") {
                    model.assignSelectedAsset(asset)
                    refreshView()
                }
                .disabled(model.target == nil || GaussianTwinInspector.assignablePayloadURL(from: asset) == nil)
                .help("Link the .untoldgs selected in the Asset Browser's Gaussians folder")

                Button("Choose…") {
                    if let url = pickGaussianPayloadFile() {
                        model.assign(payloadURL: url)
                        refreshView()
                    }
                }
                .disabled(model.target == nil)

                Button("Remove") {
                    model.removeLink()
                    refreshView()
                }
                .disabled(model.link == nil)
            }
            .controlSize(.small)

            if model.link != nil {
                ComponentForm(
                    entityId: model.entityId,
                    fields: [
                        .number(
                            label: "Swap Distance (m)",
                            get: { _ in model.swapDistance },
                            set: { _, value in model.setSwapDistance(value) }
                        ),
                        .number(
                            label: "Occluder Shrink (m)",
                            get: { _ in model.occluderShrink },
                            set: { _, value in model.setOccluderShrink(value) }
                        ),
                        .number(
                            label: "Exposure Offset (EV)",
                            get: { _ in model.exposureOffset },
                            set: { _, value in model.setExposureOffset(value) }
                        ),
                    ],
                    refresh: refreshView
                )
                Text("Swap distance 0 swaps at any distance. Exposure offset −4…4 EV.")
                    .font(.caption)
                    .foregroundColor(.editorTextTertiary)

                alignmentGroup
            }

            if let status = model.status {
                Text(status.message)
                    .font(.caption)
                    .foregroundColor(status.isError ? .editorError : .editorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.link != nil {
                if preview.isEnabled {
                    Text("Preview: \(liveState ?? "waiting for the twin system")")
                        .font(.caption)
                        .foregroundColor(.editorInfo)
                } else {
                    Text("Preview off (View > Preview Splat Twins)")
                        .font(.caption)
                        .foregroundColor(.editorTextTertiary)
                }
            }
        }
        .padding(8)
        .background(Color.editorFillSubtle)
        .cornerRadius(8)
        .onReceive(stateTimer) { _ in
            guard preview.isEnabled, model.link != nil else { return }
            liveState = model.liveTwinDescription()
        }
        .onDisappear {
            // The mode ends here, on the way out, rather than in the model's deinit: SwiftUI
            // releases the section's model inside its next update, when the section of the
            // new selection already observes the align mode, and publishing from there is a
            // runtime issue. The deinit's leave stays as the fallback.
            model.setAlignMode(false)
            model.flushPendingPersist()
        }
    }

    /// Where the splat sits in the mesh's space: offset, yaw and scale, applied live to the
    /// previewed twin and stored in the link (the runtime applies them as
    /// `GaussianComponent.splatToEntity`). Align Mode shows the splat over the mesh at any
    /// distance while the values are tuned.
    private var alignmentGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("Alignment")
                .font(.subheadline)
                .foregroundColor(.editorTextSecondary)

            ComponentForm(
                entityId: model.entityId,
                fields: [
                    .vector3(
                        label: "Offset X/Y/Z (m)",
                        get: { _ in model.alignmentOffset },
                        set: { _, value in model.setAlignmentOffset(value) }
                    ),
                    .number(
                        label: "Yaw (°)",
                        get: { _ in model.alignmentYawDegrees },
                        set: { _, value in model.setAlignmentYawDegrees(value) }
                    ),
                    .number(
                        label: "Scale",
                        get: { _ in model.alignmentScale },
                        set: { _, value in model.setAlignmentScale(value) }
                    ),
                ],
                refresh: refreshView
            )

            HStack(spacing: 10) {
                Button("Reset") {
                    model.resetAlignment()
                    refreshView()
                }
                .disabled(!model.hasAlignment)
                .help("Back to identity: the splat where the payload has it")

                Toggle("Align Mode", isOn: Binding(
                    get: { model.isAlignMode },
                    set: { on in
                        model.setAlignMode(on)
                        refreshView()
                    }
                ))
                .toggleStyle(.checkbox)
                .disabled(model.link == nil || !preview.isEnabled)
                .help("Show the splat over the mesh at any distance, occluder shells off, while the alignment is tuned. Not saved.")
            }
            .controlSize(.small)

            Text("Alignment: \(model.alignmentDescription)")
                .font(.caption)
                .foregroundColor(.editorTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.isAlignMode {
                Text("Align mode: mesh and splat both visible; shells off until it is turned off, the section leaves the screen or the scene resets.")
                    .font(.caption)
                    .foregroundColor(.editorInfo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
