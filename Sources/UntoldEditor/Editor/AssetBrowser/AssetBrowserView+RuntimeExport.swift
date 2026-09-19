//
//  AssetBrowserView+RuntimeExport.swift
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
    func queueRuntimeExport(sourceURL: URL, category: AssetCategory, destinationFolder: URL) {
        let outputExtension = category == .animations ? "untoldanim" : runtimeAssetExtension
        let outputURL = destinationFolder
            .appendingPathComponent(sourceURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension(outputExtension)
        let request = RuntimeExportRequest(
            sourceURL: sourceURL,
            category: category,
            destinationFolder: destinationFolder,
            outputURL: outputURL
        )

        runtimeExportQueue.append(request)
        presentNextRuntimeExportIfNeeded()
    }

    func presentNextRuntimeExportIfNeeded() {
        guard pendingRuntimeExport == nil, !runtimeExportQueue.isEmpty else {
            return
        }
        pendingRuntimeExport = runtimeExportQueue.removeFirst()
    }

    func runtimeExportSheet(for request: RuntimeExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cook to Untold Asset")
                .font(.title2)
                .bold()

            Text("Cook this USD or .blend source into Untold Engine's runtime format to use it in scenes: a single model becomes a .untold file, while a scene with multiple models becomes a .untoldpack bundle (one .untold per model). The source stays next to the output and can be cooked again later.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(.top, 6)
                Text(request.outputURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
                Text("If the source contains multiple models, a .untoldpack manifest is written here instead.")
                    .font(.caption2)
                    .foregroundColor(.editorTextSecondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Convert orientation", isOn: $exportConvertOrientation)

                Picker("Source orientation", selection: $exportSourceOrientation) {
                    Text("Blender native").tag("blender-native")
                    Text("Engine oriented").tag("engine-oriented")
                }
                .disabled(!exportConvertOrientation)

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
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingRuntimeExport = nil
                    presentNextRuntimeExportIfNeeded()
                }

                Button("Cook") {
                    pendingRuntimeExport = nil
                    presentNextRuntimeExportIfNeeded()
                    exportRuntimeAsset(request)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    /// Runs one export at a time; a request that arrives while another is in
    /// flight is queued and drained once the current one finishes, since
    /// spawning concurrent Blender export processes isn't safe. The sheet
    /// dismisses as soon as the user confirms (see the "Cook" button above) —
    /// progress from here on shows up in the Tasks panel, same as Gaussian
    /// cook jobs.
    func exportRuntimeAsset(_ request: RuntimeExportRequest) {
        guard !isExportingRuntimeAsset else {
            runtimeExportWorkQueue.append(request)
            return
        }
        guard let exporterScript = findExportUntoldScript() else {
            showStatus("export-untold script not found", isError: true)
            Logger.log(message: "❌ export-untold script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold")
            return
        }

        isExportingRuntimeAsset = true
        showStatus("Exporting \(request.sourceURL.lastPathComponent)...")
        let task = TaskCenter.begin(
            "Exporting \(request.sourceURL.lastPathComponent)",
            detail: "export-untold → \(request.outputURL.lastPathComponent)"
        )
        let convertOrientation = exportConvertOrientation
        let sourceOrientation = exportSourceOrientation
        let compressGeometry = exportCompressGeometry
        let compressTextures = exportCompressTextures
        let astcencBin = astcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("untold-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("untold-export-\(UUID().uuidString).err")
            task.attach(process: process)

            do {
                try FileManager.default.createDirectory(at: request.destinationFolder, withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: request.outputURL.path) {
                    try FileManager.default.removeItem(at: request.outputURL)
                }
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
                    "--output", request.outputURL.path,
                ]
                if request.category == .animations {
                    arguments.append("--animation")
                }
                if convertOrientation {
                    arguments.append("--ConvertOrientation")
                    arguments.append(contentsOf: ["--source-orientation", sourceOrientation])
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
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
                    let texturesDir = request.destinationFolder.appendingPathComponent("Textures")
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
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !patchResult.stdout.isEmpty {
                                Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if !patchResult.stderr.isEmpty {
                                Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — asset imported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                if wasCancelled {
                    // Don't leave a half-written runtime asset behind.
                    try? FileManager.default.removeItem(at: request.outputURL)
                    task.markCancelled("Cancelled by user")
                } else if exportSucceeded {
                    task.succeed("Wrote \(request.outputURL.lastPathComponent)")
                } else {
                    task.fail("export-untold exited with status \(process.terminationStatus) (see Console)")
                }

                DispatchQueue.main.async {
                    if wasCancelled {
                        Logger.log(message: "Export cancelled for \(request.sourceURL.lastPathComponent)")
                        showStatus("Export cancelled")
                    } else if exportSucceeded {
                        loadAssets()
                        showStatus("Exported \(request.outputURL.lastPathComponent)")
                    } else {
                        showStatus("Export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    }
                    finishRuntimeExport()
                }
            } catch {
                task.fail(error.localizedDescription)
                DispatchQueue.main.async {
                    Logger.log(message: "❌ Export failed: \(error)")
                    showStatus("Export failed for \(request.sourceURL.lastPathComponent)", isError: true)
                    finishRuntimeExport()
                }
            }
        }
    }

    /// Marks the current export slot free and, if a request queued up behind
    /// it while it ran, immediately starts that one.
    func finishRuntimeExport() {
        isExportingRuntimeAsset = false
        if !runtimeExportWorkQueue.isEmpty {
            exportRuntimeAsset(runtimeExportWorkQueue.removeFirst())
        }
    }
}
