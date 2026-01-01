//
//  BuildSettingsView.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import SwiftUI
import UntoldEngine

struct BuildSettingsView: View {
    @State private var projectName: String = "MyGame"
    @State private var bundleIdentifier: String = "com.yourcompany.mygame"
    @State private var selectedTarget: Int = 0
    @State private var macOSVersion: Int = 2 // v15
    @State private var includeDebugInfo: Bool = true
    @State private var optimizationLevel: Int = 0 // none
    @State private var teamID: String = ""
    @State private var outputPath: String = ""

    @State private var isBuilding: Bool = false
    @State private var buildProgress: String = ""
    @State private var showBuildResult: Bool = false
    @State private var buildResultMessage: String = ""
    @State private var buildSucceeded: Bool = false
    @State private var showBasePathAlert: Bool = false
    @State private var projectExists: Bool = false
    @State private var showProjectExistsChoice: Bool = false
    @State private var resultProjectPath: URL?

    @Environment(\.dismiss) private var dismiss

    private let targets = ["macOS", "iOS", "iOS AR", "visionOS"]
    private let macOSVersions = ["13.0", "14.0", "15.0"]
    private let optimizationLevels = ["None", "Speed", "Size"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Build Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Settings Form
            Form {
                Section("Project") {
                    TextField("Project Name", text: $projectName)
                    TextField("Bundle Identifier", text: $bundleIdentifier)
                        .textContentType(.none)
                }

                Section("Target Platform") {
                    Picker("Platform", selection: $selectedTarget) {
                        ForEach(0 ..< targets.count, id: \.self) { index in
                            Text(targets[index]).tag(index)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedTarget == 0 { // macOS
                        Picker("macOS Version", selection: $macOSVersion) {
                            ForEach(0 ..< macOSVersions.count, id: \.self) { index in
                                Text(macOSVersions[index]).tag(index)
                            }
                        }
                    }
                }

                Section("Build Options") {
                    Toggle("Include Debug Info", isOn: $includeDebugInfo)

                    Picker("Optimization", selection: $optimizationLevel) {
                        ForEach(0 ..< optimizationLevels.count, id: \.self) { index in
                            Text(optimizationLevels[index]).tag(index)
                        }
                    }
                }

                Section("Code Signing") {
                    TextField("Team ID (Optional)", text: $teamID)
                        .help("Your Apple Developer Team ID for code signing")
                }

                Section("Output") {
                    HStack {
                        TextField("Output Path", text: $outputPath)
                            .disabled(true)
                        Button("Choose...") {
                            chooseOutputPath()
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()

            // Build Progress
            if isBuilding {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(buildProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            }

            // Build Button
            HStack {
                Spacer()
                Button(projectExists ? "Continue" : "Build") {
                    guard ensureAssetBasePath() else { return }
                    if projectExists {
                        showProjectExistsChoice = true
                    } else {
                        startBuild()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding || projectName.isEmpty || bundleIdentifier.isEmpty || outputPath.isEmpty)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 550)
        .alert("Build Complete", isPresented: $showBuildResult) {
            if buildSucceeded {
                Button("Open in Finder") {
                    openBuildOutput()
                }
                Button("Open in Xcode") {
                    openInXcode()
                }
                Button("OK", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(buildResultMessage)
        }
        .alert("Set Asset Folder First", isPresented: $showBasePathAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please set the Asset Folder in the Asset Browser before building.")
        }
        .alert("Project Already Exists", isPresented: $showProjectExistsChoice) {
            Button("Cancel", role: .cancel) {}
            Button("Update Game Data") {
                startUpdateGameData()
            }
            Button("Rebuild Project", role: .destructive) {
                startBuild()
            }
        } message: {
            Text("A project named '\(projectName)' already exists at this location.\n\nUpdate Game Data: Updates only scenes, scripts, and assets (preserves your code)\n\nRebuild Project: Regenerates the entire project (WARNING: deletes all custom code)")
        }
        .onAppear {
            loadDefaultSettings()
        }
        .onChange(of: projectName) {
            checkProjectExists()
        }
        .onChange(of: outputPath) {
            checkProjectExists()
        }
    }

    private func loadDefaultSettings() {
        // Set default output path
        if let homeDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            outputPath = homeDir.appendingPathComponent("UntoldEngineBuilds").path
        }
        checkProjectExists()
    }

    private func checkProjectExists() {
        let settings = createBuildSettings()
        projectExists = BuildSystem.shared.projectExists(settings: settings)
    }

    private func chooseOutputPath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose build output directory"

        if panel.runModal() == .OK {
            outputPath = panel.url?.path ?? outputPath
        }
    }

    private func startBuild() {
        isBuilding = true
        buildProgress = "Preparing build..."

        Task {
            do {
                let settings = createBuildSettings()

                let result = try await BuildSystem.shared.build(settings: settings) { progress in
                    Task { @MainActor in
                        buildProgress = progress
                    }
                }

                await MainActor.run {
                    isBuilding = false
                    buildSucceeded = true
                    resultProjectPath = result.xcodeProjectPath.deletingLastPathComponent()
                    buildResultMessage = """
                    Build completed successfully in \(String(format: "%.2f", result.buildTime))s

                    Project: \(result.xcodeProjectPath.path)
                    Assets: \(result.bundledAssets.count) files
                    """
                    showBuildResult = true
                    checkProjectExists() // Update project existence state
                }

            } catch {
                await MainActor.run {
                    isBuilding = false
                    buildSucceeded = false
                    buildResultMessage = "Build failed: \(error.localizedDescription)"
                    showBuildResult = true
                }
            }
        }
    }

    private func startUpdateGameData() {
        isBuilding = true
        buildProgress = "Updating game data..."

        Task {
            do {
                let settings = createBuildSettings()

                let result = try await BuildSystem.shared.updateGameData(settings: settings) { progress in
                    Task { @MainActor in
                        buildProgress = progress
                    }
                }

                await MainActor.run {
                    isBuilding = false
                    buildSucceeded = true
                    resultProjectPath = result.projectPath
                    buildResultMessage = """
                    Game data updated successfully in \(String(format: "%.2f", result.updateTime))s

                    Project: \(result.projectPath.path)
                    Updated Assets: \(result.updatedAssets.count) files
                    """
                    showBuildResult = true
                }

            } catch {
                await MainActor.run {
                    isBuilding = false
                    buildSucceeded = false
                    buildResultMessage = "Update failed: \(error.localizedDescription)"
                    showBuildResult = true
                }
            }
        }
    }

    private func createBuildSettings() -> BuildSettings {
        let target: BuildTarget
        let isIOSAR = (selectedTarget == 2) // iOS AR
        
        switch selectedTarget {
        case 0: // macOS
            let version: MacOSVersion
            switch macOSVersion {
            case 0: version = .v13
            case 1: version = .v14
            case 2: version = .v15
            default: version = .v15
            }
            target = .macOS(deployment: version)
        case 1: // iOS
            target = .iOS(deployment: .v17)
        case 2: // iOS AR
            target = .iOS(deployment: .v17)
        case 3: // visionOS
            target = .visionOS(deployment: .v26)
        default:
            target = .macOS(deployment: .v15)
        }

        let optimization: OptimizationLevel
        switch optimizationLevel {
        case 0: optimization = .none
        case 1: optimization = .speed
        case 2: optimization = .size
        default: optimization = .none
        }

        return BuildSettings(
            projectName: projectName,
            bundleIdentifier: bundleIdentifier,
            outputPath: URL(fileURLWithPath: outputPath),
            target: target,
            scenes: [], // Will be populated by BuildSystem
            includeDebugInfo: includeDebugInfo,
            optimizationLevel: optimization,
            teamID: teamID.isEmpty ? nil : teamID,
            isIOSAR: isIOSAR
        )
    }

    private func openBuildOutput() {
        if let projectPath = resultProjectPath {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: projectPath.path)
        } else {
            let buildPath = URL(fileURLWithPath: outputPath).appendingPathComponent(projectName)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: buildPath.path)
        }
    }

    private func openInXcode() {
        let xcodeProjectPath = URL(fileURLWithPath: outputPath)
            .appendingPathComponent(projectName)
            .appendingPathComponent("\(projectName).xcodeproj")

        NSWorkspace.shared.open(xcodeProjectPath)
    }

    private func ensureAssetBasePath() -> Bool {
        guard EditorAssetBasePath.shared.basePath != nil else {
            showBasePathAlert = true
            return false
        }
        return true
    }
}

#Preview {
    BuildSettingsView()
}
