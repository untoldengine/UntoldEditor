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

    struct ToolbarView: View {
        @ObservedObject var selectionManager: SelectionManager

        var onSave: () -> Void
        var onSaveAs: () -> Void
        var onClear: () -> Void
        var onPlayToggled: (Bool) -> Void
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
        @State private var showBuildSettings = false
        @State private var showingNewScriptDialog = false
        @State private var newScriptName = ""
        @State private var showBasePathAlert = false

        var body: some View {
            HStack {
                leftSection

                Spacer()

                rightSection
            }
            .overlay(
                centeredButtons
            )
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
            .sheet(isPresented: $showBuildSettings) {
                BuildSettingsView()
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
            .alert("Set Asset Folder First", isPresented: $showBasePathAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please set the Asset Folder in the Asset Browser before creating or editing scripts.")
            }
        }

        var rightSection: some View {
            HStack(spacing: 12) {
                Button(action: { showBuildSettings = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                        Text("Build")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.editorAccent)
                    .foregroundColor(.black.opacity(0.9))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

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
                    .background(isPlaying ? Color.red : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Menu {
                    Button("Save", systemImage: "square.and.arrow.down.on.square", action: onSave)
                    Button("Save As…", systemImage: "square.and.arrow.down", action: onSaveAs)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down.on.square")
                        Text("Save")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.gray.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
            }
        }

        var leftSection: some View {
            HStack(spacing: 8) {
//                Button(action: onCreateCylinder) {
//                    Image(systemName: "cylinder.fill")
//                        .font(.system(size: 14))
//                        .foregroundColor(.white)
//                }
//                .padding(6)
//                .background(Color.blue.opacity(0.8))
//                .cornerRadius(6)
//                .buttonStyle(.plain)
//                .help("Add Cylinder")
//
//                Button(action: onCreateCone) {
//                    Image(systemName: "cone.fill")
//                        .font(.system(size: 14))
//                        .foregroundColor(.white)
//                }
//                .padding(6)
//                .background(Color.blue.opacity(0.8))
//                .cornerRadius(6)
//                .buttonStyle(.plain)
//                .help("Add Cone")

                Divider().frame(height: 24)

                Button(action: {
                    guard ensureAssetBasePath() else { return }
                    showingNewScriptDialog = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("New Script")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.green.opacity(0.85))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Create a new script in the Scripts project")

                Button(action: openInXcode) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                        Text("Open in Xcode")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.blue.opacity(0.85))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Open Scripts project in Xcode")
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

        private func ensureAssetBasePath() -> Bool {
            guard EditorAssetBasePath.shared.basePath != nil else {
                showBasePathAlert = true
                return false
            }
            return true
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
                    .background(Color.gray)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(PlainButtonStyle())
            .help(tooltip)
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

#endif
