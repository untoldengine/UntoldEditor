//
//  GaussianCookRequest.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UntoldEngine

/// What the asset browser presents the cook sheet for: the `.ply`/`.spz` sources of a row
/// (or of an import batch). Only `init?(sources:)` makes one, so a request always has
/// something to cook; the browser shows the sheet as this item (`.sheet(item:)`), which is
/// what keeps it from opening for "0 files".
struct GaussianCookRequest: Identifiable, Equatable {
    let id = UUID()
    /// The `.ply`/`.spz` files to cook; never empty.
    let sourceURLs: [URL]

    /// `nil` when `sources` holds no `.ply`/`.spz` (baked `.untoldgs` files are imported as
    /// they are).
    init?(sources: [URL]) {
        let plyURLs = gaussianSourcesToCook(in: sources)
        guard !plyURLs.isEmpty else { return nil }
        sourceURLs = plyURLs
    }
}

/// Heading for the cook sheet: the file name, or the batch size for an import of several.
func gaussianCookSheetSourceName(for urls: [URL]) -> String {
    urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) Gaussian splat files"
}

/// The sheet's title. With nothing to cook it asks for sources rather than announcing a
/// cook of "0 files".
func gaussianCookSheetTitle(for urls: [URL]) -> String {
    urls.isEmpty ? "Select .ply/.spz files to cook" : "Cook \(gaussianCookSheetSourceName(for: urls)) to .untoldgs"
}

/// Whether the Cook button does anything: at least one source, and a positive scale (zero
/// collapses the capture, negative mirrors it).
func gaussianCookSheetCanCook(sourceURLs: [URL], settings: GaussianCookSettings) -> Bool {
    !sourceURLs.isEmpty && settings.scale > 0
}

/// Caption under the budget row: what the budget does to the source's splats, or that
/// there is no source to count.
func gaussianCookSourceCaption(sourceURLs: [URL], sourceSplatCount: Int?, maxSplatCount: Int?) -> String {
    guard !sourceURLs.isEmpty else { return "No .ply/.spz file selected; nothing to cook." }
    return gaussianBudgetCaption(sourceCount: sourceSplatCount, maxSplatCount: maxSplatCount)
}

/// What a cook's task row says about its settings: the tiers, then `gaussianCookTaskDetailSuffix`.
func gaussianCookTaskDetail(settings: GaussianCookSettings) -> String {
    let tiers = settings.levelCount > 1 ? "\(settings.levelCount) progressive tiers " : ""
    return tiers + gaussianCookTaskDetailSuffix(settings: settings)
}

/// The tail of a cook's task row — "→ .untoldgs" and the settings that depart from the
/// defaults — shared by the queued, running and per-phase details, which each put their own
/// words in front of it.
func gaussianCookTaskDetailSuffix(settings: GaussianCookSettings) -> String {
    var detail = "→ .untoldgs"
    if settings.recenter {
        detail += ", recentred"
    }
    // The Mac cap is the default on the machine the editor runs on; only name a budget that
    // departs from it, so ordinary cooks keep their short row.
    if settings.splatBudget != .mac, let budget = settings.cookOptions.maxSplatCount {
        detail += ", budget \(GaussianSplatBudget.formatted(budget))"
    } else if settings.splatBudget == .unlimited {
        detail += ", no budget"
    }
    // Auto is the default; only a forced choice is named.
    switch settings.coarseLevels {
    case .automatic: break
    case .off: detail += ", no coarse levels"
    case .one: detail += ", 1 coarse level"
    case .two: detail += ", 2 coarse levels"
    }
    return detail
}

/// Tasks panel detail once a cook succeeded: what the cook kept, and the coarse levels the
/// tiers carry (`GaussianLODTier.coarseReport`; the tiers of a progressive bake each resolve
/// the policy on their own, so the levels are counted per tier that got some). A bake
/// without a section keeps the short row.
func gaussianCookSummary(_ report: UntoldGSCookReport, coarse: [UntoldGSCoarseLevelReport?] = []) -> String {
    var summary = "Kept \(report.keptSplatCount) of \(report.inputSplatCount) splats"
    if report.prunedByBudget > 0 {
        summary += " (\(report.prunedByBudget) over the budget dropped)"
    }
    let levelled = coarse.compactMap { $0 }
    if let first = levelled.first {
        let bytes = levelled.reduce(0) { $0 + $1.bytes }
        let levels = "\(first.levelCount) coarse level\(first.levelCount == 1 ? "" : "s")"
        let tiers = coarse.count > 1 ? " on \(levelled.count) of \(coarse.count) tiers" : ""
        summary += "; \(levels)\(tiers) (\(gaussianCookFormatBytes(bytes)))"
    }
    return summary
}

/// The summary of a whole bake: the cook report plus every tier's coarse section.
func gaussianCookSummary(_ bake: GaussianProgressiveBakeResult) -> String {
    gaussianCookSummary(bake.cookReport, coarse: bake.tiers.map(\.coarseReport))
}

/// Bytes as the engine's profile lines print them: MiB above a mebibyte, KiB above a
/// kibibyte, bytes below.
func gaussianCookFormatBytes(_ bytes: Int) -> String {
    let value = Double(bytes)
    if bytes >= 1024 * 1024 {
        return String(format: "%.2f MiB", value / 1_048_576)
    }
    if bytes >= 1024 {
        return String(format: "%.2f KiB", value / 1024)
    }
    return "\(bytes) B"
}

/// Tasks panel detail for a failed cook. The engine's own errors carry a readable
/// `description` but no localized text; Foundation errors (a missing file, say) are
/// the other way round.
func gaussianCookFailureDetail(_ error: Error) -> String {
    switch error {
    case let cancelled as GaussianCookCancelledError:
        switch cancelled.stage {
        case .queued: "Cancelled before it started"
        case .running: "Cancelled; nothing was written"
        }
    case let cook as UntoldGSCookError: cook.description
    case let format as UntoldGSError: format.description
    default: error.localizedDescription
    }
}

/// The result of a tracked cook the user cancelled from the Tasks panel. Nothing was written
/// at either stage: a queued cook never started, and a running one stops at the engine's
/// next poll with its tiers still in temporary files, which it removes.
struct GaussianCookCancelledError: Error, Equatable {
    enum Stage: Equatable {
        /// Still waiting for the serial cook queue (an import batch).
        case queued
        /// The engine's bake was under way (`UntoldGSCookError.cancelled`).
        case running
    }

    var stage: Stage
}

/// Tasks panel detail from the bake's start until the engine's first report: the size of
/// the cook and its settings. A recentred cook measures the source bounds in this time.
func gaussianCookRunningDetail(settings: GaussianCookSettings, sourceSplatCount: Int?) -> String {
    var detail = "Cooking"
    if let sourceSplatCount {
        detail += " \(GaussianSplatBudget.formatted(sourceSplatCount)) splats"
    }
    return detail + " \(gaussianCookTaskDetail(settings: settings))"
}

/// Tasks panel detail while the bake waits for the serial cook queue (an import batch cooks
/// its files one after the other); the row is cancellable until then.
func gaussianCookQueuedDetail(settings: GaussianCookSettings) -> String {
    "Waiting for the cook queue \(gaussianCookTaskDetail(settings: settings))"
}

/// Tasks panel detail for one of the engine's reports: the phase in the user's words —
/// reading and cooking name the source's splats, chunking, coarsening and writing name the
/// tier of a progressive bake — in front of the settings tail. The fraction is the row's
/// bar, so the text carries none.
func gaussianCookProgressDetail(_ progress: UntoldGSCookProgress, settings: GaussianCookSettings, sourceSplatCount: Int?) -> String {
    let splats = sourceSplatCount.map { " \(GaussianSplatBudget.formatted($0)) splats" } ?? ""
    let tier = progress.tierCount > 1 ? " tier \(progress.tierIndex + 1) of \(progress.tierCount)" : ""
    let phase = switch progress.phase {
    case .read: "Reading\(splats)"
    case .cook: "Cooking\(splats)"
    case .chunk: "Chunking\(tier)"
    case .coarsen: "Coarsening\(tier)"
    case .write: "Writing\(tier)"
    }
    return "\(phase) \(gaussianCookTaskDetailSuffix(settings: settings))"
}

/// Feeds the engine's cook reports to a Tasks-panel row at the rate the row can use. The
/// engine reports after every source window and chunk batch — thousands of times for a large
/// capture — where the panel redraws a few times a second: a change of phase or tier goes
/// through at once, so does the end of a phase (fraction 1), and the reports between them at
/// most every `minimumInterval`. The fraction shown never goes back: the engine's `overall`
/// is monotonic by construction, and the row keeps the highest value it was given regardless.
final class GaussianCookProgressReporter: @unchecked Sendable {
    /// About 10 Hz: as often as a progress bar is worth redrawing.
    static let minimumInterval: TimeInterval = 0.1

    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let detail: (UntoldGSCookProgress) -> String
    private let deliver: (_ fraction: Double, _ detail: String) -> Void
    private var lastPhase: UntoldGSCookPhase?
    private var lastTierIndex = -1
    private var lastDeliveredAt: TimeInterval = -.infinity
    private var lastFraction: Double = 0

    /// - Parameters:
    ///   - now: The clock, in seconds; tests pass their own.
    ///   - detail: The row's text for a report (`gaussianCookProgressDetail`).
    ///   - deliver: Receives the fraction and the text of every report let through, on the
    ///     cooking thread.
    init(
        now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        detail: @escaping (UntoldGSCookProgress) -> String,
        deliver: @escaping (_ fraction: Double, _ detail: String) -> Void
    ) {
        self.now = now
        self.detail = detail
        self.deliver = deliver
    }

    /// The fraction last delivered.
    var fraction: Double {
        lock.lock(); defer { lock.unlock() }
        return lastFraction
    }

    /// Passes `progress` on when the row should see it; returns whether it did.
    @discardableResult
    func report(_ progress: UntoldGSCookProgress) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let time = now()
        let phaseChanged = progress.phase != lastPhase || progress.tierIndex != lastTierIndex
        guard phaseChanged || progress.fraction >= 1 || time - lastDeliveredAt >= Self.minimumInterval else {
            return false
        }
        lastPhase = progress.phase
        lastTierIndex = progress.tierIndex
        lastDeliveredAt = time
        lastFraction = max(lastFraction, Double(progress.overall))
        deliver(lastFraction, detail(progress))
        return true
    }
}

/// Cooks `plyURL` (a `.ply` or `.spz` source) as a job in the Tasks panel. The bake runs on
/// `queue` (the shared serial cook queue by default) so the UI never blocks. The row can be
/// cancelled while the cook waits its turn on the queue (a batch of imports) and while the
/// engine bakes: the engine polls the request between source windows and chunk batches,
/// stops within a moment and removes the tiers it had staged, so nothing is written. The
/// row's bar follows the engine's reports (`GaussianCookProgressReporter`), its text names
/// the phase, and it finishes with the kept/pruned/levels summary or the error's description.
/// The source file is never modified, so a failed or cancelled cook leaves it in place to
/// re-cook from the context menu. `completion` runs on the main queue after the task is
/// finished; a cancelled cook completes with `GaussianCookCancelledError` at either stage. A
/// caller's own `control` — a test's, a script's — sees every report unthrottled and can stop
/// the cook too.
@discardableResult
func cookGaussianPLYTracked(
    plyURL: URL,
    settings: GaussianCookSettings,
    outputDirectory: URL? = nil,
    queue: DispatchQueue = gaussianCookQueue,
    control: UntoldGSCookControl? = nil,
    completion: @escaping (Result<GaussianProgressiveBakeResult, Error>) -> Void
) -> EditorTaskHandle {
    let task = TaskCenter.begin(
        "Cooking \(plyURL.lastPathComponent)",
        detail: gaussianCookQueuedDetail(settings: settings),
        // The hook itself does nothing: the queued block reads `isCancelRequested` when its
        // turn comes, and the engine polls it while the bake runs. Its presence gives the
        // row its cancel button.
        onCancel: {}
    )
    queue.async {
        if task.isCancelRequested {
            let cancelled = GaussianCookCancelledError(stage: .queued)
            task.markCancelled(gaussianCookFailureDetail(cancelled))
            DispatchQueue.main.async { completion(.failure(cancelled)) }
            return
        }
        // The count on the row: a header read for a `.ply`. A `.spz` keeps its count inside
        // the gzip payload, and a whole decode ahead of the bake's own is not worth the
        // number, so its row goes without one; the engine's reports name the phase either way.
        let sourceSplatCount = plyURL.pathExtension.lowercased() == "spz"
            ? nil
            : try? PLYReader.readGaussianSplatCount(from: plyURL)
        task.setDetail(gaussianCookRunningDetail(settings: settings, sourceSplatCount: sourceSplatCount))
        task.setProgress(0)
        let reporter = GaussianCookProgressReporter(
            detail: { gaussianCookProgressDetail($0, settings: settings, sourceSplatCount: sourceSplatCount) },
            deliver: { fraction, detail in
                // The row says "Cancelling…" from the request until the engine stops; a
                // report in between must not overwrite it.
                guard !task.isCancelRequested else { return }
                task.setProgress(fraction)
                task.setDetail(detail)
            }
        )
        let panelControl = UntoldGSCookControl(
            progress: { progress in
                control?.progress?(progress)
                reporter.report(progress)
            },
            isCancelled: { task.isCancelRequested || control?.isCancelled?() == true }
        )
        let result = Result { try cookGaussianPLY(plyURL: plyURL, settings: settings, outputDirectory: outputDirectory, control: panelControl) }
            .mapError { error -> Error in
                (error as? UntoldGSCookError) == .cancelled ? GaussianCookCancelledError(stage: .running) : error
            }
        switch result {
        case let .success(bake):
            task.succeed(gaussianCookSummary(bake))
        case let .failure(error) where error is GaussianCookCancelledError:
            task.markCancelled(gaussianCookFailureDetail(error))
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
