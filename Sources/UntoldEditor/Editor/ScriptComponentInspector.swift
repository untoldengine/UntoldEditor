//
//  ScriptComponentInspector.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

// This file were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import SwiftUI
import UntoldEngine

struct ScriptComponentInspector: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    @State private var scriptFilePath: String = ""
    @State private var scriptName: String = "No script loaded"
    @State private var triggerType: String = "-"
    @State private var executionMode: String = "-"
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Script Properties")
                .font(.headline)
                .padding(.bottom, 4)

            // Script Info Display
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Script:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(scriptName)
                        .font(.caption)
                        .lineLimit(1)
                }

                HStack {
                    Text("Trigger:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(triggerType)
                        .font(.caption)
                }

                HStack {
                    Text("Mode:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(executionMode)
                        .font(.caption)
                }

                if !scriptFilePath.isEmpty {
                    Text(scriptFilePath)
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)

            // Action Buttons
            HStack(spacing: 8) {
                // Load Script Button
                Button(action: {
                    loadScriptFile()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.white)
                        Text("Load Script")
                            .fontWeight(.regular)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                // Hot Reload Button
                if !scriptFilePath.isEmpty {
                    Button(action: {
                        hotReloadScript()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.white)
                            Text("Reload")
                                .fontWeight(.regular)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            // Error Display
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(6)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .onAppear {
            loadExistingScriptInfo()
        }
    }

    // MARK: - Load Script File

    private func loadScriptFile() {
        // Check if a script is selected in the Asset Browser
        if let selectedScript = asset,
           selectedScript.category == "Scripts",
           selectedScript.path.pathExtension.lowercased() == "uscript" {
            // Load from selected asset
            attachScriptToEntity(url: selectedScript.path)
        } else {
            // Fall back to file picker
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [.init(filenameExtension: "uscript")!]
            panel.message = "Select a USC script file"

            if panel.runModal() == .OK, let url = panel.url {
                attachScriptToEntity(url: url)
            }
        }
    }

    // MARK: - Attach Script to Entity

    private func attachScriptToEntity(url: URL) {
        do {
            // Read JSON file
            let jsonData = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let script = try decoder.decode(USCScript.self, from: jsonData)

            // Get or create ScriptComponent
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

            // Assign script
            scriptComponent.script = script
            scriptComponent.scriptFilePath = url.path

            // Update UI
            scriptFilePath = url.path
            scriptName = script.name
            triggerType = describeTriggerType(script.metadata.triggerType)
            executionMode = describeExecutionMode(script.metadata.executionMode)
            showError = false

            refreshView()

            print("[USC] Script loaded: \(script.name) from \(url.lastPathComponent)")
        } catch {
            showErrorMessage("Failed to load script: \(error.localizedDescription)")
        }
    }

    // MARK: - Hot Reload Script

    private func hotReloadScript() {
        guard !scriptFilePath.isEmpty else { return }

        let url = URL(fileURLWithPath: scriptFilePath)
        attachScriptToEntity(url: url)
    }

    // MARK: - Load Existing Script Info

    private func loadExistingScriptInfo() {
        guard let scriptComponent = scene.get(component: ScriptComponent.self, for: entityId),
              let script = scriptComponent.script
        else {
            return
        }

        scriptName = script.name
        triggerType = describeTriggerType(script.metadata.triggerType)
        executionMode = describeExecutionMode(script.metadata.executionMode)
        scriptFilePath = scriptComponent.scriptFilePath ?? ""
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
