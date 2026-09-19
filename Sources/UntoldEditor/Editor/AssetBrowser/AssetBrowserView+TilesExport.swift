//
//  AssetBrowserView+TilesExport.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

extension AssetBrowserView {
    func queueTilesExport(sourceURL: URL, destinationFolder: URL) {
        let outputDirURL = destinationFolder.appendingPathComponent("tile_exports", isDirectory: true)
        let request = TilesExportRequest(
            sourceURL: sourceURL,
            destinationFolder: destinationFolder,
            outputDirURL: outputDirURL
        )
        tilesExportQueue.append(request)
        presentNextTilesExportIfNeeded()
    }

    func presentNextTilesExportIfNeeded() {
        guard pendingTilesExport == nil, !tilesExportQueue.isEmpty else { return }
        pendingTilesExport = tilesExportQueue.removeFirst()
    }

    func tilesExportSheet(for request: TilesExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cook Tiled Stream Model")
                .font(.title2)
                .bold()

            Text("Cook this USD or .blend source into tile payloads and a manifest JSON using export-untold-tiles; the source stays next to the output.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output directory")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.top, 6)
                Text(request.outputDirURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Tile size (world units)")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("X").font(.caption)
                        TextField("25", text: $exportTileSizeX)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Y").font(.caption)
                        TextField("10000", text: $exportTileSizeY)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Z").font(.caption)
                        TextField("25", text: $exportTileSizeZ)
                            .frame(width: 70)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Toggle("Auto tile size", isOn: $exportAutoTileSize)
                Toggle("Generate HLOD", isOn: $exportGenerateHLOD)
                Toggle("Generate LOD", isOn: $exportGenerateLOD)
                Toggle("Compress geometry (LZ4)", isOn: $exportCompressGeometry)
                    .help("Compresses vertex and index data with LZ4. Requires the Python lz4 package.")
                if exportCompressGeometry {
                    Text("Requires: pip install lz4")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .padding(.leading, 20)
                }

                Toggle("Compress textures (ASTC)", isOn: $exportCompressTextures)
                    .help("Converts textures to GPU-native ASTC format. Requires astcenc and the Python Pillow package.")
                if exportCompressTextures {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Link("Install astcenc →", destination: URL(string: "https://github.com/ARM-software/astc-encoder/releases")!)
                                .font(.caption)
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            Text("Also requires: pip install Pillow")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("astcenc path (optional)")
                                .font(.caption)
                                .foregroundColor(.editorTextSecondary)
                            HStack {
                                TextField("/opt/homebrew/bin/astcenc", text: $astcencBinPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse…") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.title = "Select astcenc binary"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        astcencBinPath = url.path
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }

                Toggle("Quad-tree partitioning", isOn: $exportQuadTree)
                Toggle("Dry run", isOn: $exportDryRun)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingTilesExport = nil
                    presentNextTilesExportIfNeeded()
                }

                Button("Cook") {
                    pendingTilesExport = nil
                    presentNextTilesExportIfNeeded()
                    exportTilesAsset(request)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Same pattern as exportRuntimeAsset: dismiss immediately, queue behind
    /// an in-flight export rather than dropping the request.
    func exportTilesAsset(_ request: TilesExportRequest) {
        guard !isExportingTilesAsset else {
            tilesExportWorkQueue.append(request)
            return
        }
        guard let exporterScript = findExportUntoldTilesScript() else {
            showStatus("export-untold-tiles script not found", isError: true)
            Logger.log(message: "❌ export-untold-tiles script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold-tiles")
            return
        }

        isExportingTilesAsset = true
        showStatus("Exporting tiles for \(request.sourceURL.lastPathComponent)...")
        let task = TaskCenter.begin(
            "Exporting tiles for \(request.sourceURL.lastPathComponent)",
            detail: "export-untold-tiles → \(request.outputDirURL.lastPathComponent)/"
        )
        let tileSizeX = exportTileSizeX
        let tileSizeY = exportTileSizeY
        let tileSizeZ = exportTileSizeZ
        let compressGeometry = exportCompressGeometry
        let compressTextures = exportCompressTextures
        let astcencBin = astcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let quadTree = exportQuadTree
        let autoTileSize = exportAutoTileSize
        let generateHLOD = exportGenerateHLOD
        let generateLOD = exportGenerateLOD
        let dryRun = exportDryRun

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("untold-tiles-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("untold-tiles-export-\(UUID().uuidString).err")
            task.attach(process: process)

            do {
                try FileManager.default.createDirectory(at: request.destinationFolder, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: outputLogURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputLogURL)
                let errorHandle = try FileHandle(forWritingTo: errorLogURL)
                defer {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    try? FileManager.default.removeItem(at: outputLogURL)
                    try? FileManager.default.removeItem(at: errorLogURL)
                }

                process.executableURL = exporterScript
                var arguments = [
                    "--input", request.sourceURL.path,
                    "--output-dir", request.outputDirURL.path,
                ]
                if let x = Double(tileSizeX), x > 0 {
                    arguments.append(contentsOf: ["--tile-size-x", tileSizeX])
                }
                if let y = Double(tileSizeY), y > 0 {
                    arguments.append(contentsOf: ["--tile-size-y", tileSizeY])
                }
                if let z = Double(tileSizeZ), z > 0 {
                    arguments.append(contentsOf: ["--tile-size-z", tileSizeZ])
                }
                if autoTileSize {
                    arguments.append("--auto-tile-size")
                }
                if generateHLOD {
                    arguments.append("--generate-hlod")
                }
                if generateLOD {
                    arguments.append("--generate-lod")
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
                }
                if quadTree {
                    arguments.append("--quadtree")
                }
                if dryRun {
                    arguments.append("--dry-run")
                }
                process.arguments = arguments
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                try process.run()
                process.waitUntilExit()

                let stdout = (try? String(contentsOf: outputLogURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errorLogURL, encoding: .utf8)) ?? ""

                DispatchQueue.main.async {
                    if !stdout.isEmpty {
                        Logger.log(message: stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if !stderr.isEmpty {
                        Logger.log(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }

                let wasCancelled = task.isCancelRequested
                let exportSucceeded = process.terminationStatus == 0 && !wasCancelled

                if exportSucceeded, compressTextures {
                    let texturesDir = request.outputDirURL.appendingPathComponent("Textures")
                    if FileManager.default.fileExists(atPath: texturesDir.path),
                       let texbakeScript = findTexbakeScript()
                    {
                        task.setDetail("Baking textures (ASTC)…")
                        DispatchQueue.main.async { showStatus("Baking textures (ASTC)...") }
                        let bakeResult = runTexbakeStep(script: texbakeScript, arguments: ["--dir", texturesDir.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !bakeResult.stdout.isEmpty {
                                Logger.log(message: bakeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !bakeResult.stderr.isEmpty {
                                Logger.log(message: bakeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }

                        task.setDetail("Patching texture references…")
                        DispatchQueue.main.async { showStatus("Patching texture references...") }
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputDirURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !patchResult.stdout.isEmpty {
                                Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stderr.isEmpty {
                                Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — tiles imported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                if wasCancelled {
                    task.markCancelled("Cancelled by user")
                } else if exportSucceeded {
                    task.succeed("Wrote tiles to \(request.outputDirURL.lastPathComponent)/")
                } else {
                    task.fail("export-untold-tiles exited with status \(process.terminationStatus) (see Console)")
                }

                DispatchQueue.main.async {
                    if wasCancelled {
                        Logger.log(message: "Tiles export cancelled for \(request.sourceURL.lastPathComponent)")
                        showStatus("Tiles export cancelled")
                    } else if exportSucceeded {
                        loadAssets()
                        showStatus("Exported tiles for \(request.sourceURL.deletingPathExtension().lastPathComponent)")
                    } else {
                        showStatus("Tiles export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    }
                    finishTilesExport()
                }
            } catch {
                task.fail(error.localizedDescription)
                DispatchQueue.main.async {
                    Logger.log(message: "❌ Tiles export failed: \(error)")
                    showStatus("Tiles export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    finishTilesExport()
                }
            }
        }
    }

    /// Same pattern as finishRuntimeExport, for tiled stream-model exports.
    func finishTilesExport() {
        isExportingTilesAsset = false
        if !tilesExportWorkQueue.isEmpty {
            exportTilesAsset(tilesExportWorkQueue.removeFirst())
        }
    }
}
