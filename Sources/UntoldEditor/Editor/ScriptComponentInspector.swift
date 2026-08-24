//
//  ScriptComponentInspector.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// This file were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import SwiftUI
import UntoldEngine

struct ScriptComponentInspector: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    // We keep minimal UI state; details are read from the component each render.
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showBasePathAlert: Bool = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Script Properties")
                .font(.headline)
                .padding(.bottom, 4)

            // List all scripts attached to this entity
            if let comp = scene.get(component: ScriptComponent.self, for: entityId) {
                if comp.scripts.isEmpty {
                    Text("No scripts attached")
                        .font(.caption)
                        .foregroundColor(.editorTextSecondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.editorFill)
                        .cornerRadius(6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(comp.scripts.indices, id: \.self) { index in
                            scriptRow(comp: comp, index: index)
                        }
                    }
                }
            } else {
                Text("No Script Component found")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.editorFill)
                    .cornerRadius(6)
            }

            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    loadScriptFileAndAppend()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.editorTextPrimary)
                        Text("Load Script")
                            .fontWeight(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorInfo)
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }

            // Error Display
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.editorError)
                    .padding(6)
                    .background(Color.editorError.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .onAppear {
            // Nothing to pre-load; we render directly from the component.
        }
        .alert("Set Asset Folder First", isPresented: $showBasePathAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please set the Asset Folder in the Asset Browser before loading or creating scripts.")
        }
        .overlay(alignment: .bottom) {
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.editorTextPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(statusIsError ? Color.editorError.opacity(0.85) : Color.editorSuccess.opacity(0.85))
                    .cornerRadius(8)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    // MARK: - Script Row

    @ViewBuilder
    private func scriptRow(comp: ScriptComponent, index: Int) -> some View {
        let script = comp.scripts[index]
        let path = comp.scriptFilePaths?.indices.contains(index) == true ? comp.scriptFilePaths?[index] : nil

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Script:")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(script.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            HStack {
                Text("Trigger:")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(describeTriggerType(script.metadata.triggerType))
                    .font(.caption)
            }

            HStack {
                Text("Mode:")
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
                Text(describeExecutionMode(script.metadata.executionMode))
                    .font(.caption)
            }

            if let path, !path.isEmpty {
                Text(path)
                    .font(.system(size: 9))
                    .foregroundColor(.editorTextTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                if let path, !path.isEmpty {
                    Button(action: {
                        hotReloadScript(at: index)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.editorTextPrimary)
                            Text("Reload")
                                .fontWeight(.regular)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.editorWarning)
                        .foregroundColor(.editorTextPrimary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Button(role: .destructive, action: {
                    removeScript(at: index)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Remove")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorError)
                    .foregroundColor(.editorTextPrimary)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.editorFill)
        .cornerRadius(6)
    }

    // MARK: - Load Script File (Append)

    private func loadScriptFileAndAppend() {
        guard EditorAssetBasePath.shared.basePath != nil else {
            showBasePathAlert = true
            return
        }

        // Prefer selected asset from Asset Browser
        if let selectedScript = asset,
           selectedScript.category == "Scripts",
           selectedScript.path.pathExtension.lowercased() == "uscript"
        {
            appendScript(from: selectedScript.path)
        } else {
            // Fall back to file picker
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.init(filenameExtension: "uscript")!]
            panel.message = "Select a USC script file"

            if panel.runModal() == .OK, let url = panel.url {
                appendScript(from: url)
            }
        }
    }

    // MARK: - Append Script to Component

    private func appendScript(from url: URL) {
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let loaded = try decoder.decode(USCScript.self, from: jsonData)

            let scriptComponent: ScriptComponent
            if let existing = scene.get(component: ScriptComponent.self, for: entityId) {
                scriptComponent = existing
            } else {
                guard let newComp = scene.assign(to: entityId, component: ScriptComponent.self) else {
                    showErrorMessage("Failed to create ScriptComponent")
                    return
                }
                scriptComponent = newComp
            }

            // Append new script and its path (keeping indices aligned)
            scriptComponent.scripts.append(loaded)
            if scriptComponent.scriptFilePaths == nil {
                scriptComponent.scriptFilePaths = []
            }
            scriptComponent.scriptFilePaths?.append(url.path)

            // Update UI and notify
            showError = false
            refreshView()

            print("[USC] Script appended: \(loaded.name) from \(url.lastPathComponent)")
        } catch {
            showErrorMessage("Failed to load script: \(error.localizedDescription)")
        }
    }

    // MARK: - Hot Reload Script (by index)

    private func hotReloadScript(at index: Int) {
        guard let comp = scene.get(component: ScriptComponent.self, for: entityId),
              comp.scripts.indices.contains(index),
              let paths = comp.scriptFilePaths,
              paths.indices.contains(index)
        else { return }

        let url = URL(fileURLWithPath: paths[index])
        do {
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let reloaded = try decoder.decode(USCScript.self, from: jsonData)

            comp.scripts[index] = reloaded

            showError = false
            refreshView()

            showStatus("Script reloaded: \(reloaded.name)")
            print("[USC] Script reloaded: \(reloaded.name) from \(url.lastPathComponent)")
        } catch {
            showErrorMessage("Failed to reload script: \(error.localizedDescription)")
        }
    }

    // MARK: - Remove Script (by index)

    private func removeScript(at index: Int) {
        guard let comp = scene.get(component: ScriptComponent.self, for: entityId),
              comp.scripts.indices.contains(index)
        else { return }

        comp.scripts.remove(at: index)

        if var paths = comp.scriptFilePaths, paths.indices.contains(index) {
            paths.remove(at: index)
            comp.scriptFilePaths = paths.isEmpty ? nil : paths
        }

        refreshView()
    }

    // MARK: - Helpers

    private func showErrorMessage(_ message: String) {
        errorMessage = message
        showError = true

        // Auto-hide after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            showError = false
        }
    }

    private func showStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        statusIsError = isError

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func describeTriggerType(_ triggerType: TriggerType) -> String {
        switch triggerType {
        case .event:
            return "On Event"
        case .perFrame:
            return "On Update"
        case .manual:
            return "Manual"
        }
    }

    private func describeExecutionMode(_ executionMode: ExecutionMode) -> String {
        switch executionMode {
        case .interpreted:
            return "Interpreted"
        case .compiled:
            return "Compiled"
        case .auto:
            return "Auto"
        }
    }
}
