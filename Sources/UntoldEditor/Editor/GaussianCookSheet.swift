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
    /// Per-chunk coarse levels (`UntoldGSCookOptions.coarseLevels`): merged splats a far or
    /// not-yet-paged chunk draws instead of its fine records. Auto bakes two levels for assets
    /// of at least `UntoldGSFormat.coarseLevelsAutomaticMinimumChunks` chunks.
    var coarseLevels: GaussianCoarseLevelChoice = .automatic

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
        options.coarseLevels = coarseLevels.policy
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

/// The cook sheet's "Coarse levels" choices, mapped to `UntoldGSCoarseLevelPolicy`.
enum GaussianCoarseLevelChoice: String, CaseIterable, Identifiable {
    /// Two levels for assets of at least `UntoldGSFormat.coarseLevelsAutomaticMinimumChunks`
    /// chunks, none for smaller ones: the engine's default.
    case automatic
    /// No coarse section, whatever the size.
    case off
    /// One level (1/8 of the fine splats per chunk), whatever the size.
    case one
    /// Two levels (1/8 and 1/64), whatever the size.
    case two

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .off: "Off"
        case .one: "1"
        case .two: "2"
        }
    }

    var policy: UntoldGSCoarseLevelPolicy {
        switch self {
        case .automatic: .automatic
        case .off: .off
        case .one: .levels(count: 1)
        case .two: .levels(count: 2)
        }
    }

    /// The tooltip of the row: what the levels are for and what Auto does.
    static let summary = "Far chunks draw merged splats instead of their fine records, and a paged chunk draws them until its pages arrive. Auto bakes two levels for captures of at least \(UntoldGSFormat.coarseLevelsAutomaticMinimumChunks) chunks."
}

/// Splat budget presets: the per-entity caps the engine runtime enforces per platform
/// (`GaussianRuntimeLimits`), or no cap at all.
enum GaussianSplatBudget: String, CaseIterable, Identifiable {
    /// The engine's mobile per-entity cap (`UntoldGSCookOptions.splatBudgetMobile`): Apple
    /// Vision Pro, iPhone, iPad and Apple TV.
    case visionPro
    /// The engine's Mac per-entity cap (`UntoldGSCookOptions.splatBudgetMac`).
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

/// What the sheet knows about a source before it cooks: enough for the captions. A `.ply`
/// gives it up from the header alone, without reading the body. A `.spz` has no header-only
/// path — its count and degree sit inside the gzip payload — so it is decoded whole, as the
/// bake decodes it again.
struct GaussianCookSourceInfo: Equatable {
    var splatCount: Int
    /// Spherical-harmonics degree the file stores (0 when it has no `f_rest_*` properties).
    var shDegree: Int

    /// For a `.ply`, a header-only read: the splat count through the engine's reader and the
    /// degree from the `f_rest_N` property count of the first 100 KB (3 × ((d + 1)² − 1)
    /// coefficients). For a `.spz`, the engine's whole decode (`SPZReader.readGaussianAsset`):
    /// the count is of the splats the reader keeps, past its negligible-opacity cull, and the
    /// degree is the payload's.
    static func read(from url: URL) throws -> GaussianCookSourceInfo {
        if url.pathExtension.lowercased() == "spz" {
            let asset = try SPZReader.readGaussianAsset(from: url)
            return GaussianCookSourceInfo(splatCount: asset.splats.count, shDegree: asset.sphericalHarmonics?.degree ?? 0)
        }
        let splatCount = try PLYReader.readGaussianSplatCount(from: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 100_000) ?? Data()
        return GaussianCookSourceInfo(splatCount: splatCount, shDegree: shDegree(fromHeaderPrefix: prefix))
    }

    static func shDegree(fromHeaderPrefix prefix: Data) -> Int {
        guard let text = String(data: prefix, encoding: .ascii) ?? String(data: prefix, encoding: .isoLatin1) else { return 0 }
        let header = text.components(separatedBy: "end_header").first ?? text
        let rest = header.components(separatedBy: .newlines).filter { line in
            let fields = line.split(separator: " ")
            return fields.count == 3 && fields[0] == "property" && fields[2].hasPrefix("f_rest_")
        }.count
        switch rest {
        case 45...: return 3
        case 24...: return 2
        case 9...: return 1
        default: return 0
        }
    }
}

/// Bytes per splat of the engine's compact cook store (`UntoldGSSplatStore`): the floats of
/// position, scale, rotation, colour and opacity, 56 bytes, plus the spherical harmonics
/// already quantised to the target degree.
let gaussianCookStoreBytesPerSplat = 56

/// Process memory a cook of `splatCount` splats at `shDegree` peaks at, in bytes. The engine
/// streams the source in windows and cooks it into one compact store, so the store is what
/// the cook holds — about 100 bytes per splat at degree 3 — plus the windows in flight, the
/// ranking and the chunk encode, about half as much again: a 10 M-splat degree-3 capture
/// (a 2.25 GiB `.ply`) peaks at about 1.4 GiB. The budget compacts the store in place, so the
/// source count is what counts, not the kept count. A `.spz` is decoded whole before the cook
/// (its reader is not streamed), so the decoded asset sits beside the store through the read;
/// the estimate is a floor there.
func gaussianCookEstimatedPeakBytes(splatCount: Int, shDegree: Int) -> Int {
    let shBytes = shDegree > 0 ? UntoldGSFormat.shCoefficientCount(degree: UInt8(min(shDegree, Int(UntoldGSFormat.maxSHDegree)))) : 0
    return splatCount * (gaussianCookStoreBytesPerSplat + shBytes) * 3 / 2
}

/// Caption under the source row: what the cook costs in memory, and a warning when the
/// estimate does not fit the machine. Nil for an empty or unreadable source.
func gaussianCookMemoryCaption(splatCount: Int, shDegree: Int, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) -> String? {
    guard splatCount > 0 else { return nil }
    let peak = gaussianCookEstimatedPeakBytes(splatCount: splatCount, shDegree: shDegree)
    let text = "The cook needs about \(gaussianCookFormatGiB(peak)) of memory (this Mac has \(gaussianCookFormatGiB(Int(physicalMemory))))"
    if Double(peak) > Double(physicalMemory) * 0.75 {
        return text + "; expect heavy swapping — close other apps or cook on a Mac with more memory."
    }
    return text + "."
}

/// Bytes as a short gibibyte figure for the captions ("9.4 GiB", "512 MiB"), in the units
/// `gaussianCookFormatBytes` and the engine's profile lines use.
func gaussianCookFormatGiB(_ bytes: Int) -> String {
    let value = Double(bytes)
    if bytes >= 1 << 30 {
        return String(format: "%.1f GiB", value / Double(1 << 30))
    }
    return String(format: "%.0f MiB", value / Double(1 << 20))
}

/// Caption under the budget row: what the cooked file costs at runtime on this Mac — the
/// packed records (16 bytes plus the SH block per kept splat) against the engine's paging
/// threshold, so the user knows whether the file loads whole or pages from disk, and the
/// working set the frame draws from.
func gaussianCookRuntimeCaption(
    keptSplatCount: Int,
    shDegree: Int,
    residencyBudgetBytes: Int = GaussianPagingPolicy.residencyBudgetBytes(),
    pagePoolMaxBytes: Int = GaussianPagingPolicy.pagePoolMaxBytes,
    workingSetSplats: Int = GaussianRuntimeLimits.workingSetSplatsOverride ?? GaussianRuntimeLimits.workingSetSplats
) -> String {
    let shBytes = shDegree > 0 ? UntoldGSFormat.shCoefficientCount(degree: UInt8(min(shDegree, Int(UntoldGSFormat.maxSHDegree)))) : 0
    let packed = GaussianPagingPolicy.assetBytes(splatCount: keptSplatCount, shBytesPerSplat: shBytes)
    let threshold = GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: residencyBudgetBytes)
    var caption = "About \(gaussianCookFormatGiB(packed)) of packed splats at runtime: "
    if packed > threshold {
        let pool = min(packed, residencyBudgetBytes, pagePoolMaxBytes)
        // A zero threshold is the View > Splat Debug > Force Splat Paging switch.
        let reason = threshold == 0 ? "Force Splat Paging is on" : "above \(gaussianCookFormatGiB(threshold))"
        caption += "pages from disk (\(reason)) through a \(gaussianCookFormatGiB(pool)) pool"
    } else {
        caption += "loads whole (below \(gaussianCookFormatGiB(threshold)))"
    }
    caption += "; the frame draws at most \(GaussianSplatBudget.formatted(workingSetSplats)) splats."
    return caption
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

/// Bounds of the splat centres in a source `.ply` or `.spz`, in capture space. A `.ply` is
/// measured in one streamed pass over the positions (`PLYReader.readGaussianCenterBounds`)
/// with nothing resident but the running box, so a recentred cook of a multi-gigabyte capture
/// costs a second read of the file and no memory. A `.spz` has no streamed reader: it is
/// decoded whole (`SPZReader.readGaussianAsset`, as the bake decodes it again) and the box
/// is taken over the decoded centres. The bake's own `centerBounds` cannot serve either way:
/// they are of the cooked splats, and the recenter translation has to be in the transform
/// before the cook.
func gaussianSourceBounds(plyURL: URL) throws -> (min: simd_float3, max: simd_float3) {
    if plyURL.pathExtension.lowercased() == "spz" {
        let splats = try SPZReader.readGaussianAsset(from: plyURL).splats
        guard let first = splats.first else {
            throw UntoldGSError.sizeMismatch("source .spz contains no splats")
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
    guard let bounds = try PLYReader.readGaussianCenterBounds(from: plyURL) else {
        throw UntoldGSError.sizeMismatch("source .ply contains no splats")
    }
    return bounds
}

/// Writes `<name>.untoldgs` (or `<name>_lodN.untoldgs` tiers) beside `plyURL` (a `.ply` or
/// `.spz` source), or inside `outputDirectory` when the editor is organizing the asset as a
/// folder package. A recentred cook reads the source bounds first and bakes the offset into
/// the transform. `control` follows and stops the bake (`UntoldGSCookControl`): it is
/// polled before and after the bounds read, then the engine reports its phase and fraction
/// through it and polls its cancellation between windows and chunk batches (a `.spz` is
/// decoded whole, so its read reports once and the polling starts with the cook); a
/// cancelled bake throws `UntoldGSCookError.cancelled` with nothing written, its tiers
/// staged in temporary files until the last one is complete.
func cookGaussianPLY(
    plyURL: URL,
    settings: GaussianCookSettings,
    outputDirectory: URL? = nil,
    control: UntoldGSCookControl? = nil
) throws -> GaussianProgressiveBakeResult {
    if let outputDirectory {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }
    let outputBaseURL = outputDirectory?
        .appendingPathComponent(plyURL.deletingPathExtension().lastPathComponent)
        .appendingPathExtension("untoldgs")
        ?? plyURL.deletingPathExtension().appendingPathExtension("untoldgs")
    try control?.checkCancelled()
    let bounds = settings.recenter ? try gaussianSourceBounds(plyURL: plyURL) : nil
    // The bounds pass is the whole streamed `.ply` (or a whole `.spz` decode) with no poll of
    // its own, and the engine's first poll comes with its first report -- past a second whole
    // decode for a `.spz`. A cancel that arrived meanwhile stops here instead.
    try control?.checkCancelled()
    let cookOptions = settings.cookOptions(recenteringBounds: bounds)
    let levelCount = max(1, settings.levelCount)
    if plyURL.pathExtension.lowercased() == "spz" {
        return try bakeGaussianSplatProgressiveTiers(
            spzURL: plyURL,
            outputBaseURL: outputBaseURL,
            levelCount: levelCount,
            cookOptions: cookOptions,
            control: control
        )
    }
    return try bakeGaussianSplatProgressiveTiers(
        plyURL: plyURL,
        outputBaseURL: outputBaseURL,
        levelCount: levelCount,
        cookOptions: cookOptions,
        control: control
    )
}

/// Bakes run one at a time: the engine baker saturates the cores on its own, and an
/// import batch of several `.ply` files should queue up rather than contend.
let gaussianCookQueue = DispatchQueue(label: "com.untoldengine.editor.gaussian-cook", qos: .userInitiated)

/// The files an import batch should cook: `.ply` or `.spz` sources. Baked `.untoldgs` files
/// are imported as they are.
func gaussianSourcesToCook(in urls: [URL]) -> [URL] {
    urls.filter { ["ply", "spz"].contains($0.pathExtension.lowercased()) }
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

/// `info.baseFilename` is whatever project-relative-or-absolute identifier the scene file
/// happened to store (see `GaussianSceneData.baseFilename` in the engine's `SceneSerializer`) —
/// not necessarily an absolute path, unlike every `EditorGaussianLoadPlan.progressive` built
/// from a fresh pick via `editorGaussianLoadPlan(for:maxDistances:)`, which always derives
/// `baseFilename` from a resolved file URL. Reconstructs that same absolute-path shape instead,
/// from the tier-0 URL the engine already resolved onto the just-restored entity's
/// `GaussianLODComponent` — cheap string manipulation, no disk probing (unlike
/// `progressiveGaussianTiers(for:)`, which counts tiers by checking file existence).
private func resolvedProgressiveBaseFilename(entityId: EntityID, levelCount: Int) -> String? {
    guard let tierZeroURL = scene.get(component: GaussianLODComponent.self, for: entityId)?.lodLevels.first?.url else {
        return nil
    }
    let noExtension = tierZeroURL.deletingPathExtension()
    let name = noExtension.lastPathComponent
    guard levelCount > 1, name.hasSuffix("_lod0") else {
        return noExtension.path
    }
    let baseName = String(name.dropLast("_lod0".count))
    return noExtension.deletingLastPathComponent().appendingPathComponent(baseName).path
}

/// Rebuilds this entity's `EditorGaussianAssetState` entry from what `deserializeScene` already
/// resolved for it, so the Inspector's Gaussian panel reflects a splat restored from a
/// `.untoldscene` the same way it reflects one just dropped or assigned interactively —
/// without re-reading the asset off disk. Pass as `deserializeScene`'s
/// `onGaussianEntityRestored` callback.
func restoreEditorGaussianState(entityId: EntityID, info: GaussianSceneRestoreInfo) {
    let plan: EditorGaussianLoadPlan
    if info.isProgressive, let levelCount = info.levelCount, let maxDistances = info.maxDistances,
       let baseFilename = resolvedProgressiveBaseFilename(entityId: entityId, levelCount: levelCount)
    {
        plan = .progressive(baseFilename: baseFilename, levelCount: levelCount, maxDistances: maxDistances)
    } else {
        plan = .single(filename: info.sourceURL.deletingPathExtension().path, withExtension: info.fileExtension)
    }

    EditorGaussianAssetState.shared.setMetadata(
        EditorGaussianAssetMetadata(sourceURL: info.sourceURL, plan: plan),
        for: entityId
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

    // A whole-resident load of a large file takes seconds with nothing on screen: the Tasks
    // panel shows it, with what the engine is about to do with the file.
    let task = TaskCenter.begin("Loading \(url.lastPathComponent)", detail: "Reading \(url.lastPathComponent)")

    switch plan {
    case let .progressive(baseFilename, levelCount, maxDistances):
        // The engine has no asynchronous progressive loader: the tiers read on the main thread.
        task.setDetail("\(levelCount) progressive tiers, resident")
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
        task.succeed()
        completion?(true)
        return true

    case let .single(filename, withExtension):
        Task {
            // The index read (header, chunk table, tree) is bounded; the payload comes through
            // the engine's loader below, off the main thread.
            let detail = await Task.detached { gaussianPlacementDetail(for: url) }.value
            task.setDetail(detail)
            let success = await setEntityGaussianAsync(entityId: entityId, url: url)
            DispatchQueue.main.async {
                if success {
                    task.succeed(detail)
                } else {
                    task.fail("The engine declined \(url.lastPathComponent) (see Console)")
                }
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

    setEntityGaussianTileStreaming(
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
