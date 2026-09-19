//
//  EditorView+Project.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    func openExistingProjectFromWelcome() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Select the UntoldEngine project folder (the folder containing the .xcodeproj file)"
        panel.prompt = "Open Project"

        guard panel.runModal() == .OK, let projectURL = panel.url else {
            showWelcomeStart = true
            return
        }
        openProject(at: projectURL)
    }

    /// Validates and opens the project folder at `projectURL`. Shared by the Open panel and the
    /// `--open-project` launch argument.
    @discardableResult
    func openProject(at projectURL: URL) -> Bool {
        let fm = FileManager.default
        let projectName = projectURL.lastPathComponent
        let xcodeProjectPath = projectURL.appendingPathComponent("\(projectName).xcodeproj")
        // XcodeGen projects are defined by project.yml; the .xcodeproj is generated from it and
        // is often not checked in, so either one marks a project folder.
        let projectSpecPath = projectURL.appendingPathComponent("project.yml")
        guard fm.fileExists(atPath: xcodeProjectPath.path) || fm.fileExists(atPath: projectSpecPath.path) else {
            invalidProjectMessage = "This doesn't appear to be a valid UntoldEngine project.\n\nExpected to find: \(projectName).xcodeproj or project.yml"
            showInvalidProjectAlert = true
            showWelcomeStart = true
            return false
        }

        let gameDataPath = projectURL
            .appendingPathComponent("Sources")
            .appendingPathComponent(projectName)
            .appendingPathComponent("GameData")

        if !fm.fileExists(atPath: gameDataPath.path) {
            do {
                try fm.createDirectory(at: gameDataPath, withIntermediateDirectories: true)
                print("📁 Created missing GameData folder structure")
            } catch {
                invalidProjectMessage = "Failed to create GameData folder structure:\n\n\(error.localizedDescription)"
                showInvalidProjectAlert = true
                showWelcomeStart = true
                return false
            }
        }

        let assetFolders = ["Models", "StreamModels", "Animations", "Scenes", "Scripts", "Gaussians", "Materials", "HDR", "Shaders", "LUT"]
        for folder in assetFolders {
            let folderURL = gameDataPath.appendingPathComponent(folder, isDirectory: true)
            if !fm.fileExists(atPath: folderURL.path) {
                try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
        }

        NotificationCenter.default.post(name: .projectWillSwitch, object: nil)
        assetBasePath = gameDataPath
        EditorAssetBasePath.shared.basePath = gameDataPath

        print("✅ Opened project: \(projectName)")
        print("📁 Asset base path set to: \(gameDataPath.path)")
        return true
    }

    // MARK: - Project Switching Cleanup

    /// Cleans up the editor state when switching projects.
    /// Clears all entities, resets cameras/lights, and prepares for new project.
    func cleanupForProjectSwitch() {
        print("🧹 Cleaning up for project switch...")

        // Reuse the existing clear scene logic (handles entities, cameras, lights, etc.)
        editor_clearScene()

        // Clear selected asset
        selectedAsset = nil

        // Clear assets dictionary (will be repopulated by Asset Browser)
        assets = [:]

        // Clear current scene URL
        editorController?.currentSceneURL = nil

        print("✅ Editor cleaned up for new project")
    }
}
