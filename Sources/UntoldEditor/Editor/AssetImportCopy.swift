//
//  AssetImportCopy.swift
//  UntoldEditor
//
//  Importing an asset copies its source into the project as a job in the Tasks panel.
//  The copy runs off the main thread and is written to a hidden sibling first, so the
//  content panel never lists a half-copied file; once it is done the item is moved into
//  place. A copy that runs longer than `assetImportPlaceholderDelay` gets a placeholder
//  row (icon + file name) in the content panel until it finishes.
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// How long an import copy may run before the content panel shows a placeholder row
/// for it. Small files finish well inside this and simply appear when they are done.
let assetImportPlaceholderDelay: TimeInterval = 5

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

/// Runs an import copy as a job in the Tasks panel. `work` receives the staging URL and
/// writes the imported item there (a file, or a folder with its contents); when it
/// returns, the item is moved to `destination`. Everything runs on `queue`, never on the
/// main thread. A failure removes the staging item so nothing half-copied is left behind.
/// `completion` runs on the main queue after the task is finished.
@discardableResult
func importAssetTracked(
    destination: URL,
    detail: String = "",
    queue: DispatchQueue = assetImportQueue,
    fileManager fm: FileManager = .default,
    work: @escaping (URL) throws -> Void,
    completion: @escaping (Result<URL, Error>) -> Void
) -> EditorTaskHandle {
    let name = destination.lastPathComponent
    let task = TaskCenter.begin("Importing \(name)", detail: detail)
    queue.async {
        let staging = assetImportStagingURL(for: destination)
        let result = Result<URL, Error> {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            do {
                try work(staging)
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
        case let .failure(error):
            task.fail(error.localizedDescription)
        }
        DispatchQueue.main.async { completion(result) }
    }
    return task
}
