//
//  GaussianCookSheet.swift
//  UntoldEditor
//
//  "Cook to .untoldgs" for a Gaussian splat .ply in the asset browser: the options
//  the engine's baker takes (progressive tiers, spherical-harmonics degree, chunk
//  size, axis flip, scale, opacity floor) and the call that writes the tiers next
//  to the source file. Runs in-process through the engine, no CLI needed.
//  `cookGaussianPLYTracked` is the entry point the browser uses: it queues the bake
//  off the main thread and reports it as a job in the Tasks panel.
//

import simd
import SwiftUI
import UntoldEngine

/// Editable state behind the sheet. Mirrors `untoldengine export --splat-*`.
struct GaussianCookSettings: Equatable {
    /// Number of progressive tiers; 1 writes a single `<name>.untoldgs`.
    var levelCount: Int = 1
    /// Spherical-harmonics degree to keep; `nil` keeps the source degree.
    var shDegree: Int?
    /// Splats per chunk: 1024 for objects, 4096 for environments.
    var chunkSplats: Int = 1024
    /// Convert from the 3DGS training convention (Y down, Z forward) to the engine's.
    var flipYZ: Bool = false
    var scale: Float = 1
    var minimumOpacity: Float = 0.005

    var cookOptions: UntoldGSCookOptions {
        var options = UntoldGSCookOptions()
        options.log2ChunkSplats = UInt8(max(1, chunkSplats.trailingZeroBitCount))
        options.shDegree = shDegree.map { UInt8($0) }
        options.minimumOpacity = minimumOpacity
        var transform = simd_float4x4(diagonal: [scale, scale, scale, 1])
        if flipYZ {
            transform = simd_mul(simd_float4x4(diagonal: [1, -1, -1, 1]), transform)
        }
        options.transform = transform
        return options
    }
}

/// Writes `<ply name>.untoldgs` (or `<ply name>_lodN.untoldgs` tiers) beside `plyURL`.
func cookGaussianPLY(plyURL: URL, settings: GaussianCookSettings) throws -> GaussianProgressiveBakeResult {
    let outputURL = plyURL.deletingPathExtension().appendingPathExtension("untoldgs")
    return try bakeGaussianSplatProgressiveTiers(
        plyURL: plyURL,
        outputBaseURL: outputURL,
        levelCount: max(1, settings.levelCount),
        cookOptions: settings.cookOptions
    )
}

/// Bakes run one at a time: the engine baker saturates the cores on its own, and an
/// import batch of several `.ply` files should queue up rather than contend.
let gaussianCookQueue = DispatchQueue(label: "com.untoldengine.editor.gaussian-cook", qos: .userInitiated)

/// The files an import batch should cook: `.ply` sources. Baked `.untoldgs` files are
/// imported as they are.
func gaussianSourcesToCook(in urls: [URL]) -> [URL] {
    urls.filter { $0.pathExtension.lowercased() == "ply" }
}

/// Heading for the cook sheet: the file name, or the batch size for an import of several.
func gaussianCookSheetSourceName(for urls: [URL]) -> String {
    urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) .ply files"
}

/// Tasks panel detail while a cook runs. The baker reports no progress, so this is all
/// the row shows next to its spinner.
func gaussianCookTaskDetail(settings: GaussianCookSettings) -> String {
    settings.levelCount > 1 ? "\(settings.levelCount) progressive tiers → .untoldgs" : "→ .untoldgs"
}

/// Tasks panel detail once a cook succeeded.
func gaussianCookSummary(_ report: UntoldGSCookReport) -> String {
    "Kept \(report.keptSplatCount) of \(report.inputSplatCount) splats"
}

/// Tasks panel detail for a failed cook. The engine's own errors carry a readable
/// `description` but no localized text; Foundation errors (a missing file, say) are
/// the other way round.
func gaussianCookFailureDetail(_ error: Error) -> String {
    switch error {
    case let cook as UntoldGSCookError: cook.description
    case let format as UntoldGSError: format.description
    default: error.localizedDescription
    }
}

/// Cooks `plyURL` as a job in the Tasks panel. The bake runs on `queue` (the shared
/// serial cook queue by default) so the UI never blocks; the task is indeterminate
/// and finishes with the kept/pruned summary or the error's description. The `.ply`
/// is never modified, so a failed cook leaves it in place to re-cook from the
/// context menu. `completion` runs on the main queue after the task is finished.
@discardableResult
func cookGaussianPLYTracked(
    plyURL: URL,
    settings: GaussianCookSettings,
    queue: DispatchQueue = gaussianCookQueue,
    completion: @escaping (Result<GaussianProgressiveBakeResult, Error>) -> Void
) -> EditorTaskHandle {
    let task = TaskCenter.begin(
        "Cooking \(plyURL.lastPathComponent)",
        detail: gaussianCookTaskDetail(settings: settings)
    )
    queue.async {
        let result = Result { try cookGaussianPLY(plyURL: plyURL, settings: settings) }
        switch result {
        case let .success(bake):
            task.succeed(gaussianCookSummary(bake.cookReport))
        case let .failure(error):
            task.fail(gaussianCookFailureDetail(error))
        }
        DispatchQueue.main.async { completion(result) }
    }
    return task
}

/// For `<base>_lodN.untoldgs`, the progressive base name and the number of sibling tiers.
func progressiveGaussianTiers(for url: URL) -> (baseURL: URL, levelCount: Int)? {
    let stem = url.deletingPathExtension().lastPathComponent
    guard let range = stem.range(of: #"_lod\d+$"#, options: .regularExpression) else { return nil }
    let base = String(stem[..<range.lowerBound])
    let directory = url.deletingLastPathComponent()
    var count = 0
    while FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(base)_lod\(count).untoldgs").path) {
        count += 1
    }
    guard count > 0 else { return nil }
    return (directory.appendingPathComponent(base), count)
}

/// Distance thresholds for `levelCount` tiers: finest inside 5 units, then ×3 per tier.
func defaultGaussianLODDistances(levelCount: Int) -> [Float] {
    (0 ..< levelCount).map { index in
        index == levelCount - 1 ? .greatestFiniteMagnitude : 5 * pow(3, Float(index))
    }
}

struct GaussianCookSheet: View {
    let sourceName: String
    @Binding var settings: GaussianCookSettings
    var onCook: () -> Void
    var onCancel: () -> Void

    private let shDegreeChoices: [(label: String, value: Int?)] = [
        ("Source", nil), ("0 (none)", 0), ("1", 1), ("2", 2), ("3", 3),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cook \(sourceName) to .untoldgs")
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
                    Text("Axes")
                    Toggle("Flip Y/Z (3DGS training convention)", isOn: $settings.flipYZ)
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
            }

            Text("Writes the file next to the source .ply. Re-cook after changing the .ply; version 3 files replace any earlier .untoldgs of the same name.")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Cook", action: onCook)
                    .keyboardShortcut(.defaultAction)
                    .disabled(settings.scale <= 0)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
