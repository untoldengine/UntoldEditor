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
        @ObservedObject private var statsStore = EditorEngineStatsStore.shared
        private let editorVersionLabel = "v0.14.2"

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

        @State private var isPlaying = false
        @State private var showCreateProject = false
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

                rightSection
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

                Divider().frame(height: 24)

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

                Divider().frame(height: 24)

                Toggle(isOn: Binding(
                    get: { statsStore.overlayMode != .off },
                    set: { enabled in
                        if enabled {
                            statsStore.setOverlaySimplifiedEnabled(true)
                        } else {
                            statsStore.setOverlaySimplifiedEnabled(false)
                            statsStore.setOverlayAdvancedEnabled(false)
                        }
                    }
                )) {
                    Text("FPS")
                        .font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.switch)
                .scaleEffect(0.85)
                .frame(height: 20)

                Toggle(isOn: Binding(
                    get: { statsStore.overlayMode == .advanced },
                    set: { enabled in
                        if enabled {
                            statsStore.setOverlayAdvancedEnabled(true)
                        } else if statsStore.overlayMode != .off {
                            statsStore.setOverlaySimplifiedEnabled(true)
                        }
                    }
                )) {
                    Text("FPS Advanced")
                        .font(.system(size: 11, weight: .semibold))
                }
                .toggleStyle(.checkbox)
                .disabled(statsStore.overlayMode == .off)
            }
        }

        var rightSection: some View {
            HStack(spacing: 8) {
                Divider().frame(height: 24)

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
            let assetFolders = ["Models", "StreamModels", "Animations", "Scenes", "Scripts", "Gaussians", "Materials", "HDR", "Shaders"]
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
