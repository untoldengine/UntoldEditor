//
//  ToolbarView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
#if canImport(AppKit)
    import AppKit
    import SwiftUI
    import UntoldEngine

    struct ToolbarView: View {
        @ObservedObject var selectionManager: SelectionManager
        @ObservedObject var editorBasePath = EditorAssetBasePath.shared
        private let editorVersionLabel = "v0.12.3"

        var onSave: () -> Void
        var onSaveAs: () -> Void
        var onClear: () -> Void
        var onPlayToggled: (Bool) -> Void
        @Binding var useSceneCameraDuringPlay: Bool
        var dirLightCreate: () -> Void
        var pointLightCreate: () -> Void
        var spotLightCreate: () -> Void
        var areaLightCreate: () -> Void
        var onCreateCube: () -> Void
        var onCreateSphere: () -> Void
        var onCreatePlane: () -> Void
        var onCreateCylinder: () -> Void
        var onCreateCone: () -> Void
        var onQuickPreview: () -> Void

        @State private var isPlaying = false
        @State private var showCreateProject = false
        @State private var showingNewScriptDialog = false
        @State private var newScriptName = ""
        @State private var showBasePathAlert = false
        @State private var showInvalidProjectAlert = false
        @State private var invalidProjectMessage = ""

        var body: some View {
            HStack {
                if EditorFeatureFlags.enableBuildButton {
                    leftSection
                }

                Spacer()
                centeredButtons
                Spacer()

                if EditorFeatureFlags.enableScriptButtons {
                    rightSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [Color.editorPanelBackground.opacity(0.95), Color.editorPanelBackground.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .sheet(isPresented: $showCreateProject) {
                CreateProjectView()
            }
            .sheet(isPresented: $showingNewScriptDialog) {
                NewScriptDialog(
                    scriptName: $newScriptName,
                    onCancel: {
                        showingNewScriptDialog = false
                        newScriptName = ""
                    },
                    onCreate: {
                        createNewScript()
                    }
                )
            }
            .alert("No Project Loaded", isPresented: $showBasePathAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please create a new project or open an existing project before working with scripts.")
            }
            .alert("Invalid Project", isPresented: $showInvalidProjectAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(invalidProjectMessage)
            }
        }

        var leftSection: some View {
            HStack(spacing: 12) {
                Button(action: { showCreateProject = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                        Text("New")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.editorSurface)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button(action: openExistingProject) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                        Text("Open")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.editorSurface)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)

                Button(action: onQuickPreview) {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.fill")
                        Text("Quick Preview")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.editorAccent)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Preview a 3D file without creating a project")

                Divider().frame(height: 24)
            }
        }

        var centeredButtons: some View {
            HStack(spacing: 12) {
                ToolbarButton(iconName: "gobackward", action: onClear, tooltip: "Clear Scene")

                Button(action: {
                    isPlaying.toggle()
                    onPlayToggled(isPlaying)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        Text(isPlaying ? "Pause" : "Play")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(isPlaying ? Color.editorSecondaryAccent : Color.editorAccent)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .focusable(false)

                Toggle(isOn: $useSceneCameraDuringPlay) {
                    Text("Scene Cam")
                        .font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.switch)
                .scaleEffect(0.85)
                .frame(height: 20)

                Menu {
                    Button("Save Scene", systemImage: "square.and.arrow.down.on.square", action: onSave)
                    Button("Save Scene As…", systemImage: "square.and.arrow.down", action: onSaveAs)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.on.square")
                        Text("Save Scene")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
            }
        }

        var rightSection: some View {
            HStack(spacing: 8) {
                Divider().frame(height: 24)

                // Consolidated Script menu (matches Save menu pattern)
                Menu {
                    Button("New Script", systemImage: "plus.circle.fill") {
                        guard ensureAssetBasePath() else { return }
                        showingNewScriptDialog = true
                    }
                    Button("Script in Xcode", systemImage: "hammer.fill", action: openInXcode)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text.fill")
                        Text("Script")
                        // Experimental indicator
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorAccent)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .focusable(false)
                .help("USC Scripts (Experimental) - API subject to change")

                // Show project name if loaded
                if let projectName = editorBasePath.projectName {
                    Text(projectName)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.editorAccent.opacity(0.3))
                        .cornerRadius(6)
                }

                Text(editorVersionLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.editorSurface.opacity(0.6))
                    .cornerRadius(6)
            }
        }

        // MARK: - Script Management Functions

        private func createNewScript() {
            guard ensureAssetBasePath() else { return }
            let manager = ScriptProjectManager.shared

            // Initialize project if needed
            if !manager.isProjectInitialized() {
                do {
                    try manager.initializeProject()
                    print("✅ Script project initialized!")
                } catch {
                    print("❌ Failed to initialize project: \(error.localizedDescription)")
                    showingNewScriptDialog = false
                    newScriptName = ""
                    return
                }
            }

            // Create the script
            do {
                try manager.createNewScript(name: newScriptName)
                print("✅ Script \(newScriptName).swift created!")
                print("⚠️ Don't forget to add generate\(newScriptName)(to:) to GenerateScripts.swift main()")
            } catch {
                print("❌ Failed to create script: \(error.localizedDescription)")
            }

            showingNewScriptDialog = false
            newScriptName = ""
        }

        private func openInXcode() {
            guard ensureAssetBasePath() else { return }
            let manager = ScriptProjectManager.shared

            // Initialize project if needed
            if !manager.isProjectInitialized() {
                do {
                    try manager.initializeProject()
                    print("✅ Script project initialized! Opening in Xcode...")
                } catch {
                    print("❌ Failed to initialize: \(error.localizedDescription)")
                    return
                }
            }

            // Open Package.swift in Xcode
            guard let scriptsDir = manager.scriptsDirectory() else {
                print("❌ Scripts directory not found")
                return
            }

            let packageSwiftPath = scriptsDir.appendingPathComponent("Package.swift")

            // Use NSWorkspace to open the file with default app (Xcode)
            NSWorkspace.shared.open(packageSwiftPath)
            print("✅ Opening Scripts project in Xcode")
        }

        private func openExistingProject() {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = false
            panel.message = "Select the UntoldEngine project folder (the folder containing the .xcodeproj file)"
            panel.prompt = "Open Project"

            guard panel.runModal() == .OK, let projectURL = panel.url else {
                return
            }

            // Validate project structure
            let fm = FileManager.default
            let projectName = projectURL.lastPathComponent

            // Check for .xcodeproj
            let xcodeProjectPath = projectURL.appendingPathComponent("\(projectName).xcodeproj")
            guard fm.fileExists(atPath: xcodeProjectPath.path) else {
                invalidProjectMessage = "This doesn't appear to be a valid UntoldEngine project.\n\nExpected to find: \(projectName).xcodeproj"
                showInvalidProjectAlert = true
                return
            }

            // Build the GameData path
            let gameDataPath = projectURL
                .appendingPathComponent("Sources")
                .appendingPathComponent(projectName)
                .appendingPathComponent("GameData")

            // Check if GameData exists, create if not
            if !fm.fileExists(atPath: gameDataPath.path) {
                do {
                    try fm.createDirectory(at: gameDataPath, withIntermediateDirectories: true)
                    print("📁 Created missing GameData folder structure")
                } catch {
                    invalidProjectMessage = "Failed to create GameData folder structure:\n\n\(error.localizedDescription)"
                    showInvalidProjectAlert = true
                    return
                }
            }

            // Create standard asset subfolders if they don't exist
            let assetFolders = ["Models", "Animations", "Scenes", "Scripts", "Gaussians", "Materials", "HDR", "Shaders"]
            for folder in assetFolders {
                let folderURL = gameDataPath.appendingPathComponent(folder, isDirectory: true)
                if !fm.fileExists(atPath: folderURL.path) {
                    try? fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
                }
            }

            // Notify editor to clean up before switching projects
            NotificationCenter.default.post(name: .projectWillSwitch, object: nil)

            // Set the asset base path
            assetBasePath = gameDataPath
            EditorAssetBasePath.shared.basePath = gameDataPath

            print("✅ Opened project: \(projectName)")
            print("📁 Asset base path set to: \(gameDataPath.path)")
        }

        private func ensureAssetBasePath() -> Bool {
            guard EditorAssetBasePath.shared.basePath != nil else {
                showBasePathAlert = true
                return false
            }
            return true
        }
    }

    // MARK: - New Script Dialog

    struct NewScriptDialog: View {
        @Binding var scriptName: String
        let onCancel: () -> Void
        let onCreate: () -> Void

        var body: some View {
            VStack(spacing: 16) {
                Text("Create New Script")
                    .font(.headline)

                TextField("Script Name (e.g., PlayerController)", text: $scriptName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 300)

                Text("Name should be alphanumeric and start with a letter.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("Create") {
                        onCreate()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(scriptName.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 400)
        }
    }

    // MARK: - Toolbar Button Component

    struct ToolbarButton: View {
        let iconName: String
        let action: () -> Void
        let tooltip: String

        var body: some View {
            Button(action: action) {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.editorSurface)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            .focusable(false)
            .help(tooltip)
        }
    }

#endif
