//
//  AssetImportCopy.swift
//  UntoldEditor
//
//  Importing an asset copies its source into the project as a job in the Tasks panel.
//  The copy runs off the main thread and is written to a hidden sibling first, so the
//  content panel never lists a half-copied file; once it is done the item is moved into
//  place. The job reports bytes copied against the total, can be cancelled, and a copy
//  that runs longer than `assetImportPlaceholderDelay` gets a placeholder row (icon,
//  file name, progress) in the content panel until it finishes.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// How long an import copy may run before the content panel shows a placeholder row
/// for it. Same-volume copies are APFS clones and finish at once, so they never show one.
let assetImportPlaceholderDelay: TimeInterval = 1

/// Serial queue for import copies so they never block the UI and run one at a time.
let assetImportQueue = DispatchQueue(label: "com.untoldengine.editor.asset-import", qos: .userInitiated)

/// An import whose copy is still running. The content panel draws a placeholder for it
/// (in the folder that will receive it) once `showsPlaceholder` is set.
struct PendingAssetImport: Identifiable, Equatable {
    let id = UUID()
    let destinationURL: URL
    let isFolder: Bool
    /// Set after the copy has run longer than `assetImportPlaceholderDelay`.
    var showsPlaceholder = false
    /// Bytes copied so far, once the copy has reported anything.
    var progress: AssetCopyProgress?

    var name: String {
        destinationURL.lastPathComponent
    }
}

/// The pending imports that should be drawn as placeholders in `folder`: those past the
/// delay whose destination lands directly in that folder.
func placeholderImports(_ pending: [PendingAssetImport], in folder: URL) -> [PendingAssetImport] {
    let folderPath = folder.standardizedFileURL.path
    return pending.filter {
        $0.showsPlaceholder && $0.destinationURL.deletingLastPathComponent().standardizedFileURL.path == folderPath
    }
}

/// Where an import is written before it is moved to `destination`: a hidden sibling, so
/// directory listings (which skip hidden files) never show the item until it is complete.
func assetImportStagingURL(for destination: URL) -> URL {
    destination.deletingLastPathComponent()
        .appendingPathComponent(".importing-\(UUID().uuidString.prefix(8))-\(destination.lastPathComponent)")
}

/// Moves a finished staging item to `destination`. A staged folder landing on an existing
/// folder is merged into it (staged items replace same-named ones, the rest is kept), so
/// re-importing a source keeps the cooked output that already sits next to it. Anything
/// else replaces what was there.
func commitStagedImport(from staging: URL, to destination: URL, fileManager fm: FileManager = .default) throws {
    var stagingIsDir: ObjCBool = false
    var destinationIsDir: ObjCBool = false
    let stagingExists = fm.fileExists(atPath: staging.path, isDirectory: &stagingIsDir)
    let destinationExists = fm.fileExists(atPath: destination.path, isDirectory: &destinationIsDir)
    guard stagingExists else {
        throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: staging.path])
    }

    if stagingIsDir.boolValue, destinationExists, destinationIsDir.boolValue {
        let items = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: [])
        for item in items {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if fm.fileExists(atPath: target.path) {
                try fm.removeItem(at: target)
            }
            try fm.moveItem(at: item, to: target)
        }
        try fm.removeItem(at: staging)
        return
    }

    if destinationExists {
        try fm.removeItem(at: destination)
    }
    try fm.moveItem(at: staging, to: destination)
}

// MARK: - Copying with progress

/// Bytes copied so far against the total, for the Tasks row and the placeholder.
struct AssetCopyProgress: Equatable {
    let copied: Int64
    let total: Int64

    /// 0…1, or `nil` when the total is unknown (empty item).
    var fraction: Double? {
        total > 0 ? min(Double(copied) / Double(total), 1) : nil
    }
}

/// "12.3 MB of 744 MB"
func assetCopyProgressDetail(_ progress: AssetCopyProgress) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return "\(formatter.string(fromByteCount: progress.copied)) of \(formatter.string(fromByteCount: progress.total))"
}

/// Size of a file, or the sum of every file under a folder.
func assetItemByteCount(at url: URL, fileManager fm: FileManager = .default) -> Int64 {
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
    if isDir.boolValue {
        let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
        return children.reduce(0) { $0 + assetItemByteCount(at: $1, fileManager: fm) }
    }
    return (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
}

/// Copies a file or a folder tree from `source` to `destination`, reporting bytes copied.
/// A same-volume copy is an APFS clone and completes at once (progress jumps to the
/// total); otherwise the data is streamed in chunks so the progress is real and
/// `isCancelled` is honoured between chunks (throwing `CancellationError`). Modification
/// dates are kept, like `FileManager.copyItem`.
func copyAssetItem(
    from source: URL,
    to destination: URL,
    fileManager fm: FileManager = .default,
    allowClone: Bool = true,
    isCancelled: () -> Bool = { false },
    progress: (AssetCopyProgress) -> Void = { _ in }
) throws {
    let total = assetItemByteCount(at: source, fileManager: fm)
    if allowClone, clonefile(source.path, destination.path, 0) == 0 {
        progress(AssetCopyProgress(copied: total, total: total))
        return
    }

    var copied: Int64 = 0
    var lastReport = Date.distantPast
    func report(force: Bool) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.1 else { return }
        lastReport = now
        progress(AssetCopyProgress(copied: copied, total: total))
    }

    func copyFile(_ src: URL, _ dst: URL) throws {
        let input = try FileHandle(forReadingFrom: src)
        defer { try? input.close() }
        guard fm.createFile(atPath: dst.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: dst.path])
        }
        let output = try FileHandle(forWritingTo: dst)
        defer { try? output.close() }
        while true {
            if isCancelled() {
                throw CancellationError()
            }
            let chunk = try input.read(upToCount: 4 << 20) ?? Data()
            if chunk.isEmpty {
                break
            }
            try output.write(contentsOf: chunk)
            copied += Int64(chunk.count)
            report(force: false)
        }
        if let date = (try? fm.attributesOfItem(atPath: src.path))?[.modificationDate] {
            try? fm.setAttributes([.modificationDate: date], ofItemAtPath: dst.path)
        }
    }

    func copyTree(_ src: URL, _ dst: URL) throws {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path, isDirectory: &isDir) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: src.path])
        }
        if isDir.boolValue {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            for child in try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: []) {
                if isCancelled() {
                    throw CancellationError()
                }
                try copyTree(child, dst.appendingPathComponent(child.lastPathComponent))
            }
        } else {
            try copyFile(src, dst)
        }
    }

    try copyTree(source, destination)
    report(force: true)
}

// MARK: - Tracked import

/// What an import job's `work` gets: where to write, the task to poll for cancellation,
/// and a copy helper that reports progress to the task.
struct AssetImportContext {
    let stagingURL: URL
    let task: EditorTaskHandle
    let report: (AssetCopyProgress) -> Void

    /// Copies `source` to `destination` (a file or a folder) with progress on the task.
    /// Throws `CancellationError` if the user cancelled the job.
    func copy(_ source: URL, to destination: URL, fileManager fm: FileManager = .default) throws {
        try copyAssetItem(
            from: source,
            to: destination,
            fileManager: fm,
            isCancelled: { task.isCancelRequested },
            progress: report
        )
    }
}

/// Runs an import copy as a job in the Tasks panel. `work` writes the imported item to
/// the context's staging URL (a file, or a folder with its contents) using the context's
/// `copy`, so the row shows bytes copied and can be cancelled; when it returns, the item
/// is moved to `destination`. Everything runs on `queue`, never on the main thread. A
/// failure or a cancel removes the staging item so nothing half-copied is left behind.
/// `onProgress` and `completion` run on the main queue.
@discardableResult
func importAssetTracked(
    destination: URL,
    detail: String = "",
    queue: DispatchQueue = assetImportQueue,
    fileManager fm: FileManager = .default,
    onProgress: ((AssetCopyProgress) -> Void)? = nil,
    work: @escaping (AssetImportContext) throws -> Void,
    completion: @escaping (Result<URL, Error>) -> Void
) -> EditorTaskHandle {
    let name = destination.lastPathComponent
    let task = TaskCenter.begin("Importing \(name)", detail: detail, progress: 0, onCancel: {})
    queue.async {
        let staging = assetImportStagingURL(for: destination)
        let report: (AssetCopyProgress) -> Void = { progress in
            task.setProgress(progress.fraction)
            let bytes = assetCopyProgressDetail(progress)
            task.setDetail(detail.isEmpty ? bytes : "\(detail) · \(bytes)")
            if let onProgress {
                DispatchQueue.main.async { onProgress(progress) }
            }
        }
        let result = Result<URL, Error> {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try work(AssetImportContext(stagingURL: staging, task: task, report: report))
                if task.isCancelRequested {
                    throw CancellationError()
                }
                try commitStagedImport(from: staging, to: destination, fileManager: fm)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
            return destination
        }
        switch result {
        case .success:
            task.succeed("Copied \(name)")
        case .failure(is CancellationError):
            task.markCancelled("Cancelled")
        case let .failure(error):
            task.fail(error.localizedDescription)
        }
        DispatchQueue.main.async { completion(result) }
    }
    return task
}
