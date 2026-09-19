//
//  GaussianCookSheet.swift
//  UntoldEditor
//
//  "Cook to .untoldgs" for a Gaussian splat .ply or .spz in the asset browser: the
//  options the engine's baker takes (progressive tiers, spherical-harmonics degree,
//  chunk size, up axis, scale, opacity floor) and the call that writes the tiers next
//  to the source file. Runs in-process through the engine, no CLI needed. `.spz`
//  support is limited to legacy gzip versions 2-3, matching the engine's SPZReader.
//  `cookGaussianPLYTracked` is the entry point the browser uses: it queues the bake
//  off the main thread and reports it as a job in the Tasks panel, with the engine's
//  phase and fraction on the row and the cancel button wired to the engine's
//  cancellation, so a running cook stops within a moment and leaves nothing behind.
//

import simd
import SwiftUI
import UntoldEngine

struct GaussianCookSheet: View {
    /// The `.ply`/`.spz` files about to be cooked; a single file's splat count is shown under
    /// the budget row (cheap header read for `.ply`; a full decode for `.spz`, which has no
    /// header-only count). Empty (nothing selected) disables Cook and says so, so the sheet
    /// stays honest however it was presented.
    let sourceURLs: [URL]
    @Binding var settings: GaussianCookSettings
    var onCook: () -> Void
    var onCancel: () -> Void
    @State private var sourceInfo: GaussianCookSourceInfo?

    private var sourceSplatCount: Int? {
        sourceInfo?.splatCount
    }

    private let shDegreeChoices: [(label: String, value: Int?)] = [
        ("Source", nil), ("0 (none)", 0), ("1", 1), ("2", 2), ("3", 3),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(gaussianCookSheetTitle(for: sourceURLs))
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Progressive tiers")
                    Stepper(value: $settings.levelCount, in: 1 ... 4) {
                        Text("\(settings.levelCount)")
                    }
                }
                GridRow {
                    Text("Spherical harmonics")
                    Picker("", selection: $settings.shDegree) {
                        ForEach(shDegreeChoices, id: \.label) { choice in
                            Text(choice.label).tag(choice.value)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Splats per chunk")
                    Picker("", selection: $settings.chunkSplats) {
                        Text("1024 (object)").tag(1024)
                        Text("4096 (environment)").tag(4096)
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Coarse levels")
                    Picker("", selection: $settings.coarseLevels) {
                        ForEach(GaussianCoarseLevelChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                    .help(GaussianCoarseLevelChoice.summary)
                }
                GridRow {
                    Text("Up axis")
                    Picker("", selection: $settings.upAxis) {
                        Text("Y up (engine convention)").tag(UntoldGSCaptureUpAxis.y)
                        Text("Z up (scanner, CAD)").tag(UntoldGSCaptureUpAxis.z)
                        Text("−Y up (3DGS training convention)").tag(UntoldGSCaptureUpAxis.negativeY)
                    }
                    .labelsHidden()
                }
                GridRow {
                    Text("Scale")
                    TextField("1.0", value: $settings.scale, format: .number)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Opacity floor")
                    TextField("0.005", value: $settings.minimumOpacity, format: .number)
                        .frame(width: 80)
                }
                GridRow {
                    Text("Splat budget")
                    HStack(spacing: 10) {
                        Picker("", selection: $settings.splatBudget) {
                            ForEach(GaussianSplatBudget.allCases) { budget in
                                Text(budget.label).tag(budget)
                            }
                        }
                        .labelsHidden()
                        if settings.splatBudget == .custom {
                            TextField("splats", value: $settings.customSplatBudget, format: .number)
                                .frame(width: 100)
                        }
                    }
                }
                GridRow {
                    Text("")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(gaussianCookSourceCaption(sourceURLs: sourceURLs, sourceSplatCount: sourceSplatCount, maxSplatCount: settings.cookOptions.maxSplatCount))
                        if let sourceInfo {
                            // The runtime cost of the kept splats, so the paging threshold and
                            // the working set are no surprise once the file is placed.
                            Text(gaussianCookRuntimeCaption(
                                keptSplatCount: min(sourceInfo.splatCount, settings.cookOptions.maxSplatCount ?? sourceInfo.splatCount),
                                shDegree: settings.shDegree ?? sourceInfo.shDegree
                            ))
                            // The cook's own footprint: the compact store at the degree it
                            // keeps, over every source splat.
                            if let memory = gaussianCookMemoryCaption(splatCount: sourceInfo.splatCount, shDegree: min(settings.shDegree ?? sourceInfo.shDegree, sourceInfo.shDegree)) {
                                Text(memory)
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                GridRow {
                    Text("Recenter")
                    HStack(spacing: 10) {
                        Toggle("Move to the origin", isOn: $settings.recenter)
                        if settings.recenter {
                            Picker("", selection: $settings.recenterMode) {
                                ForEach(GaussianRecenterMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }

            Text("Writes the file next to the source .ply/.spz. Re-cook after changing the source; version 3 files replace any earlier .untoldgs of the same name. Recenter bakes a translation so the capture no longer sits wherever the training run left it.")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Cook", action: onCook)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!gaussianCookSheetCanCook(sourceURLs: sourceURLs, settings: settings))
            }
        }
        .padding(20)
        .frame(width: 440)
        .task(id: sourceURLs) {
            // .ply: a header-only read, cheap however large the capture. .spz has no
            // header-only count (the point count lives inside the gzip payload), so this
            // decodes the whole file -- batches show no count either way. The read runs off
            // the main actor so a large .spz never freezes the sheet; the guard drops the
            // result once the selection has moved on and a newer task owns `sourceInfo`.
            guard sourceURLs.count == 1, let url = sourceURLs.first else {
                sourceInfo = nil
                return
            }
            let info = await Task.detached(priority: .userInitiated) {
                try? GaussianCookSourceInfo.read(from: url)
            }.value
            guard !Task.isCancelled else { return }
            sourceInfo = info
        }
    }
}
