//
//  GaussianCookSheet.swift
//  UntoldEditor
//
//  "Cook to .untoldgs" for a Gaussian splat .ply in the asset browser: the options
//  the engine's baker takes (progressive tiers, spherical-harmonics degree, chunk
//  size, up axis, scale, opacity floor) and the call that writes the tiers next
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
    /// Which axis points up in the capture; the cook rotates it to the engine's Y-up frame.
    var upAxis: UntoldGSCaptureUpAxis = .y
    /// Legacy spelling of the 3DGS training convention (−Y up).
    var flipYZ: Bool {
        get { upAxis == .negativeY }
        set { upAxis = newValue ? .negativeY : .y }
    }

    var scale: Float = 1
    var minimumOpacity: Float = 0.005
    /// How many splats the cook may keep; the least important go first. Defaults to the Mac's
    /// runtime cap, the machine the editor runs on. A file meant for Vision Pro needs its cap.
    var splatBudget: GaussianSplatBudget = .mac
    /// Splat count for `GaussianSplatBudget.custom`.
    var customSplatBudget: Int = GaussianSplatBudget.visionPro.maxSplatCount ?? 0
    /// Bake a translation so the capture sits at the origin instead of wherever the
    /// training run left it. The cook reads the source bounds first to compute it.
    var recenter: Bool = false
    var recenterMode: GaussianRecenterMode = .baseOnGround

    /// Options without recentering: the up-axis rotation and scale only.
    var cookOptions: UntoldGSCookOptions {
        cookOptions(recenteringBounds: nil)
    }

    /// Options with the recenter translation baked in after the up-axis rotation and scale, computed
    /// from the source splat-centre bounds. `nil` bounds (or `recenter` off) leave the
    /// capture where it is.
    func cookOptions(recenteringBounds bounds: (min: simd_float3, max: simd_float3)?) -> UntoldGSCookOptions {
        var options = UntoldGSCookOptions()
        options.log2ChunkSplats = UInt8(max(1, chunkSplats.trailingZeroBitCount))
        options.shDegree = shDegree.map { UInt8($0) }
        options.minimumOpacity = minimumOpacity
        options.maxSplatCount = splatBudget == .custom ? max(1, customSplatBudget) : splatBudget.maxSplatCount
        var transform = UntoldGSCookOptions.transform(upAxis: upAxis, scale: scale)
        if recenter, let bounds {
            let translation = gaussianRecenterTranslation(
                boundsMin: bounds.min,
                boundsMax: bounds.max,
                transform: transform,
                mode: recenterMode
            )
            var translate = matrix_identity_float4x4
            translate.columns.3 = simd_float4(translation, 1)
            transform = simd_mul(translate, transform)
        }
        options.transform = transform
        return options
    }
}

/// Where a recentred capture's bounding box ends up.
enum GaussianRecenterMode: String, CaseIterable, Identifiable {
    /// Centred on X and Z with its lowest point on Y = 0: props that stand on the floor.
    case baseOnGround
    /// Box centre at the origin: objects meant to be rotated or floated.
    case centreAtOrigin

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .baseOnGround: "Base on the ground"
        case .centreAtOrigin: "Centre at the origin"
        }
    }
}

/// Splat budget presets: the per-entity caps the engine runtime enforces per platform
/// (`GaussianRuntimeLimits`), or no cap at all.
enum GaussianSplatBudget: String, CaseIterable, Identifiable {
    /// 5,242,880 splats: Apple Vision Pro, iPhone, iPad and Apple TV.
    case visionPro
    /// 16,777,216 splats: Mac only.
    case mac
    case custom
    case unlimited

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .visionPro: "Vision Pro, iPhone, iPad (\(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMobile)))"
        case .mac: "Mac (\(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMac)))"
        case .custom: "Custom"
        case .unlimited: "Unlimited (may not load)"
        }
    }

    /// The cook option for the preset; `nil` for unlimited and for custom (read the field).
    var maxSplatCount: Int? {
        switch self {
        case .visionPro: UntoldGSCookOptions.splatBudgetMobile
        case .mac: UntoldGSCookOptions.splatBudgetMac
        case .custom, .unlimited: nil
        }
    }

    /// Fixed English grouping, so captions and task rows read the same on every machine.
    static func formatted(_ count: Int) -> String {
        count.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }
}

/// What a budget does to a source of `sourceCount` splats (after the other pruning steps,
/// which usually drop few), for the sheet's caption.
func gaussianBudgetCaption(sourceCount: Int?, maxSplatCount: Int?) -> String {
    guard let sourceCount else {
        return maxSplatCount.map { "Keeps at most \(GaussianSplatBudget.formatted($0)) splats per file." } ?? "No splat budget."
    }
    let source = GaussianSplatBudget.formatted(sourceCount)
    guard let maxSplatCount else {
        return sourceCount > UntoldGSCookOptions.splatBudgetMobile
            ? "\(source) splats in the source; unlimited files above \(GaussianSplatBudget.formatted(UntoldGSCookOptions.splatBudgetMobile)) do not load on Vision Pro, iPhone or iPad."
            : "\(source) splats in the source, all kept."
    }
    if sourceCount <= maxSplatCount {
        return "\(source) splats in the source, within the budget."
    }
    return "\(source) splats in the source; the budget keeps the \(GaussianSplatBudget.formatted(maxSplatCount)) most important."
}

/// Translation that moves a capture's bounding box, after `transform` has been applied to
/// it, where `mode` says. The box is transformed corner by corner so a flip or scale is
/// accounted for before the offset is measured.
func gaussianRecenterTranslation(
    boundsMin: simd_float3,
    boundsMax: simd_float3,
    transform: simd_float4x4,
    mode: GaussianRecenterMode
) -> simd_float3 {
    var transformedMin = simd_float3(repeating: .greatestFiniteMagnitude)
    var transformedMax = simd_float3(repeating: -.greatestFiniteMagnitude)
    for corner in 0 ..< 8 {
        let source = simd_float3(
            corner & 1 == 0 ? boundsMin.x : boundsMax.x,
            corner & 2 == 0 ? boundsMin.y : boundsMax.y,
            corner & 4 == 0 ? boundsMin.z : boundsMax.z
        )
        let moved = simd_mul(transform, simd_float4(source, 1))
        let point = simd_float3(moved.x, moved.y, moved.z)
        transformedMin = simd_min(transformedMin, point)
        transformedMax = simd_max(transformedMax, point)
    }
    let centre = (transformedMin + transformedMax) / 2
    switch mode {
    case .baseOnGround:
        return -simd_float3(centre.x, transformedMin.y, centre.z)
    case .centreAtOrigin:
        return -centre
    }
}

/// Bounds of the splat centres in a source `.ply`, in capture space. Reads the whole
/// file, so a recentred cook parses the source twice (once here, once in the baker).
func gaussianSourceBounds(plyURL: URL) throws -> (min: simd_float3, max: simd_float3) {
    let splats = try PLYReader.readGaussianSplats(from: plyURL)
    guard let first = splats.first else {
        throw UntoldGSError.sizeMismatch("source .ply contains no splats")
    }
    var boundsMin = simd_float3(first.center.x, first.center.y, first.center.z)
    var boundsMax = boundsMin
    for splat in splats.dropFirst() {
        let centre = simd_float3(splat.center.x, splat.center.y, splat.center.z)
        boundsMin = simd_min(boundsMin, centre)
        boundsMax = simd_max(boundsMax, centre)
    }
    return (boundsMin, boundsMax)
}

/// Writes `<ply name>.untoldgs` (or `<ply name>_lodN.untoldgs` tiers) beside `plyURL`,
/// or inside `outputDirectory` when the editor is organizing the asset as a folder package.
/// A recentred cook reads the source bounds first and bakes the offset into the transform.
func cookGaussianPLY(
    plyURL: URL,
    settings: GaussianCookSettings,
    outputDirectory: URL? = nil
) throws -> GaussianProgressiveBakeResult {
    if let outputDirectory {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
    let outputBaseURL = outputDirectory?
        .appendingPathComponent(plyURL.deletingPathExtension().lastPathComponent)
        .appendingPathExtension("untoldgs")
        ?? plyURL.deletingPathExtension().appendingPathExtension("untoldgs")
    let bounds = settings.recenter ? try gaussianSourceBounds(plyURL: plyURL) : nil
    return try bakeGaussianSplatProgressiveTiers(
        plyURL: plyURL,
        outputBaseURL: outputBaseURL,
        levelCount: max(1, settings.levelCount),
        cookOptions: settings.cookOptions(recenteringBounds: bounds)
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

func gaussianPackageName(for sourceURL: URL) -> String {
    let stem = sourceURL.deletingPathExtension().lastPathComponent
    guard sourceURL.pathExtension.lowercased() == "untoldgs",
          let range = stem.range(of: #"_lod\d+$"#, options: .regularExpression)
    else {
        return stem
    }
    return String(stem[..<range.lowerBound])
}

func gaussianPackageFolder(for sourceURL: URL, in categoryRoot: URL) -> URL {
    categoryRoot.appendingPathComponent(gaussianPackageName(for: sourceURL), isDirectory: true)
}

func importGaussianAsset(
    sourceURL: URL,
    destinationFolder: URL,
    fileManager fm: FileManager = .default,
    copy: ((URL, URL) throws -> Void)? = nil
) throws -> URL {
    let copyFile = copy ?? { try fm.copyItem(at: $0, to: $1) }
    try fm.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

    let sources: [URL]
    if sourceURL.pathExtension.lowercased() == "untoldgs",
       let tiers = progressiveGaussianTiers(for: sourceURL)
    {
        sources = (0 ..< tiers.levelCount).map {
            tiers.baseURL.deletingLastPathComponent()
                .appendingPathComponent("\(tiers.baseURL.lastPathComponent)_lod\($0).untoldgs")
        }
    } else {
        sources = [sourceURL]
    }

    for source in sources {
        let destinationURL = destinationFolder.appendingPathComponent(source.lastPathComponent)
        if destinationURL.standardizedFileURL.path == source.standardizedFileURL.path {
            continue
        }
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }
        try copyFile(source, destinationURL)
    }

    return primaryGaussianAsset(in: destinationFolder, fileManager: fm)
        ?? destinationFolder.appendingPathComponent(sourceURL.lastPathComponent)
}

func primaryGaussianAsset(in folder: URL, fileManager fm: FileManager = .default) -> URL? {
    guard let contents = try? fm.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    let untoldGSFiles = contents
        .filter { $0.pathExtension.lowercased() == "untoldgs" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

    if let progressiveEntry = untoldGSFiles.first(where: { progressiveGaussianTiers(for: $0) != nil }) {
        return progressiveEntry
    }

    let folderName = folder.lastPathComponent
    if let namedSingle = untoldGSFiles.first(where: { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }) {
        return namedSingle
    }
    if untoldGSFiles.count == 1 {
        return untoldGSFiles[0]
    }

    let plyFiles = contents
        .filter { $0.pathExtension.lowercased() == "ply" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    return plyFiles.first { $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(folderName) == .orderedSame }
        ?? (plyFiles.count == 1 ? plyFiles.first : nil)
}

/// Heading for the cook sheet: the file name, or the batch size for an import of several.
func gaussianCookSheetSourceName(for urls: [URL]) -> String {
    urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) .ply files"
}

/// Tasks panel detail while a cook runs. The baker reports no progress, so this is all
/// the row shows next to its spinner.
func gaussianCookTaskDetail(settings: GaussianCookSettings) -> String {
    var detail = settings.levelCount > 1 ? "\(settings.levelCount) progressive tiers → .untoldgs" : "→ .untoldgs"
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
    return detail
}

/// Tasks panel detail once a cook succeeded.
func gaussianCookSummary(_ report: UntoldGSCookReport) -> String {
    var summary = "Kept \(report.keptSplatCount) of \(report.inputSplatCount) splats"
    if report.prunedByBudget > 0 {
        summary += " (\(report.prunedByBudget) over the budget dropped)"
    }
    return summary
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
    outputDirectory: URL? = nil,
    queue: DispatchQueue = gaussianCookQueue,
    completion: @escaping (Result<GaussianProgressiveBakeResult, Error>) -> Void
) -> EditorTaskHandle {
    let task = TaskCenter.begin(
        "Cooking \(plyURL.lastPathComponent)",
        detail: gaussianCookTaskDetail(settings: settings)
    )
    queue.async {
        let result = Result { try cookGaussianPLY(plyURL: plyURL, settings: settings, outputDirectory: outputDirectory) }
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

enum EditorGaussianLoadPlan: Equatable {
    case single(filename: String, withExtension: String)
    case progressive(baseFilename: String, levelCount: Int, maxDistances: [Float])
}

enum EditorGaussianLoadingMode: String, CaseIterable, Equatable {
    case resident = "Resident"
    case streaming = "Streaming"
}

struct EditorGaussianStreamingSettings: Equatable {
    var streamingRadius: Float = 100
    var unloadRadius: Float = 150
    var priority: Int = 0
}

struct EditorGaussianAssetMetadata: Equatable {
    let sourceURL: URL
    let plan: EditorGaussianLoadPlan
    var loadingMode: EditorGaussianLoadingMode = .resident
    var streamingSettings = EditorGaussianStreamingSettings()

    var progressiveLevelCount: Int? {
        guard case let .progressive(_, levelCount, _) = plan else { return nil }
        return levelCount
    }

    var progressiveMaxDistances: [Float]? {
        guard case let .progressive(_, _, maxDistances) = plan else { return nil }
        return maxDistances
    }
}

final class EditorGaussianAssetState {
    static let shared = EditorGaussianAssetState()

    private var metadataByEntity: [EntityID: EditorGaussianAssetMetadata] = [:]

    func metadata(for entityId: EntityID) -> EditorGaussianAssetMetadata? {
        metadataByEntity[entityId]
    }

    func setMetadata(_ metadata: EditorGaussianAssetMetadata, for entityId: EntityID) {
        metadataByEntity[entityId] = metadata
    }

    func clear(entityId: EntityID) {
        metadataByEntity[entityId] = nil
    }

    func clear() {
        metadataByEntity.removeAll()
    }
}

/// The editor's default Gaussian policy: progressive tier sets load as resident LOD assets;
/// every other .ply/.untoldgs loads as a single resident asset off the main thread.
func editorGaussianLoadPlan(for url: URL, maxDistances: [Float]? = nil) -> EditorGaussianLoadPlan? {
    let ext = url.pathExtension.lowercased()
    guard ext == "ply" || ext == "untoldgs" else { return nil }

    if ext == "untoldgs", let tiers = progressiveGaussianTiers(for: url) {
        let distances = editorNormalizedGaussianLODDistances(
            maxDistances ?? defaultGaussianLODDistances(levelCount: tiers.levelCount),
            levelCount: tiers.levelCount
        )
        return .progressive(
            baseFilename: tiers.baseURL.path,
            levelCount: tiers.levelCount,
            maxDistances: distances
        )
    }

    return .single(
        filename: url.deletingPathExtension().path,
        withExtension: ext
    )
}

@discardableResult
func loadEditorGaussianAuto(
    entityId: EntityID,
    url: URL,
    maxDistances: [Float]? = nil,
    loadingMode: EditorGaussianLoadingMode = .resident,
    streamingSettings: EditorGaussianStreamingSettings = EditorGaussianStreamingSettings(),
    completion: ((Bool) -> Void)? = nil
) -> Bool {
    guard let plan = editorGaussianLoadPlan(for: url, maxDistances: maxDistances) else {
        completion?(false)
        return false
    }

    if loadingMode == .streaming {
        return loadEditorGaussianStreaming(
            entityId: entityId,
            url: url,
            plan: plan,
            streamingSettings: streamingSettings,
            completion: completion
        )
    }

    switch plan {
    case let .progressive(baseFilename, levelCount, maxDistances):
        removeEntityGaussian(entityId: entityId)
        scene.remove(component: StreamingComponent.self, from: entityId)
        setEntityGaussian(
            entityId: entityId,
            source: .progressive(
                baseFilename: baseFilename,
                levelCount: levelCount,
                maxDistances: maxDistances
            )
        )
        EditorGaussianAssetState.shared.setMetadata(
            EditorGaussianAssetMetadata(
                sourceURL: url,
                plan: plan,
                loadingMode: .resident,
                streamingSettings: streamingSettings
            ),
            for: entityId
        )
        completion?(true)
        return true

    case let .single(filename, withExtension):
        Task {
            let success = await setEntityGaussianAsync(entityId: entityId, url: url)
            DispatchQueue.main.async {
                if success {
                    EditorGaussianAssetState.shared.setMetadata(
                        EditorGaussianAssetMetadata(
                            sourceURL: url,
                            plan: .single(filename: filename, withExtension: withExtension),
                            loadingMode: .resident,
                            streamingSettings: streamingSettings
                        ),
                        for: entityId
                    )
                } else {
                    EditorGaussianAssetState.shared.clear(entityId: entityId)
                }
                completion?(success)
            }
        }
        return true
    }
}

private func loadEditorGaussianStreaming(
    entityId: EntityID,
    url: URL,
    plan: EditorGaussianLoadPlan,
    streamingSettings: EditorGaussianStreamingSettings,
    completion: ((Bool) -> Void)?
) -> Bool {
    let normalizedSettings = editorNormalizedGaussianStreamingSettings(streamingSettings)
    guard GeometryStreamingSystem.shared.enabled else {
        Logger.logWarning(message: "[Gaussian] Streaming mode requires an active streamed scene.")
        completion?(false)
        return false
    }

    guard url.pathExtension.lowercased() == "untoldgs" else {
        Logger.logWarning(message: "[Gaussian] Streaming mode requires a baked .untoldgs asset.")
        completion?(false)
        return false
    }

    scene.remove(component: StreamingComponent.self, from: entityId)

    let source: GaussianSource
    switch plan {
    case let .single(filename, withExtension):
        source = .single(filename: filename, withExtension: withExtension)
    case let .progressive(baseFilename, levelCount, maxDistances):
        source = .progressive(
            baseFilename: baseFilename,
            levelCount: levelCount,
            maxDistances: maxDistances
        )
    }

    setEntityGaussianStreaming(
        entityId: entityId,
        source: source,
        options: GaussianStreamingOptions(
            streamingRadius: normalizedSettings.streamingRadius,
            unloadRadius: normalizedSettings.unloadRadius,
            priority: normalizedSettings.priority
        )
    )

    let registered = scene.get(component: StreamingComponent.self, for: entityId)?.assetKind == .gaussianSplat
    if registered {
        if case .single = plan {
            removeEntityGaussian(entityId: entityId)
        }
        EditorGaussianAssetState.shared.setMetadata(
            EditorGaussianAssetMetadata(
                sourceURL: url,
                plan: plan,
                loadingMode: .streaming,
                streamingSettings: normalizedSettings
            ),
            for: entityId
        )
    } else {
        Logger.logWarning(message: "[Gaussian] Failed to register streaming Gaussian. Move the entity inside a streamed tile and try again.")
    }
    completion?(registered)
    return registered
}

func editorNormalizedGaussianStreamingSettings(_ settings: EditorGaussianStreamingSettings) -> EditorGaussianStreamingSettings {
    let streamingRadius = max(settings.streamingRadius, Float.leastNonzeroMagnitude)
    return EditorGaussianStreamingSettings(
        streamingRadius: streamingRadius,
        unloadRadius: max(settings.unloadRadius, streamingRadius + 0.001),
        priority: settings.priority
    )
}

func editorNormalizedGaussianLODDistances(_ distances: [Float], levelCount: Int) -> [Float] {
    guard levelCount > 0 else { return [] }
    let defaults = defaultGaussianLODDistances(levelCount: levelCount)
    var normalized = (0 ..< levelCount).map { index in
        index < distances.count ? distances[index] : defaults[index]
    }

    for index in 0 ..< max(0, levelCount - 1) {
        let minimum = index == 0 ? Float.leastNonzeroMagnitude : normalized[index - 1] + 0.001
        if normalized[index].isFinite == false || normalized[index] < minimum {
            normalized[index] = minimum
        }
    }
    normalized[levelCount - 1] = .greatestFiniteMagnitude
    return normalized
}

func updateEditorGaussianLODDistance(entityId: EntityID, lodIndex: Int, maxDistance: Float) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId),
          let levelCount = metadata.progressiveLevelCount,
          var distances = metadata.progressiveMaxDistances,
          lodIndex >= 0,
          lodIndex < levelCount - 1
    else { return false }

    distances[lodIndex] = maxDistance
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: distances,
        loadingMode: metadata.loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func resetEditorGaussianLODDistances(entityId: EntityID) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId),
          let levelCount = metadata.progressiveLevelCount
    else { return false }

    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: defaultGaussianLODDistances(levelCount: levelCount),
        loadingMode: metadata.loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func updateEditorGaussianLoadingMode(entityId: EntityID, loadingMode: EditorGaussianLoadingMode) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) else { return false }
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: metadata.progressiveMaxDistances,
        loadingMode: loadingMode,
        streamingSettings: metadata.streamingSettings
    )
}

func updateEditorGaussianStreamingSettings(entityId: EntityID, settings: EditorGaussianStreamingSettings) -> Bool {
    guard let metadata = EditorGaussianAssetState.shared.metadata(for: entityId) else { return false }
    return loadEditorGaussianAuto(
        entityId: entityId,
        url: metadata.sourceURL,
        maxDistances: metadata.progressiveMaxDistances,
        loadingMode: metadata.loadingMode,
        streamingSettings: settings
    )
}

struct GaussianCookSheet: View {
    let sourceName: String
    /// The `.ply` files about to be cooked; a single file's header gives the splat count shown
    /// under the budget row.
    var sourceURLs: [URL] = []
    @Binding var settings: GaussianCookSettings
    var onCook: () -> Void
    var onCancel: () -> Void
    @State private var sourceSplatCount: Int?

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
                    Text(gaussianBudgetCaption(sourceCount: sourceSplatCount, maxSplatCount: settings.cookOptions.maxSplatCount))
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
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

            Text("Writes the file next to the source .ply. Re-cook after changing the .ply; version 3 files replace any earlier .untoldgs of the same name. Recenter bakes a translation so the capture no longer sits wherever the training run left it.")
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
        .task(id: sourceURLs) {
            // Header-only read, so it is cheap however large the capture; batches show no count.
            guard sourceURLs.count == 1, let url = sourceURLs.first else {
                sourceSplatCount = nil
                return
            }
            sourceSplatCount = try? PLYReader.readGaussianSplatCount(from: url)
        }
    }
}
