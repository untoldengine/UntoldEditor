//
//  ToolbarView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
#if canImport(AppKit)
    import SwiftUI

    struct ToolbarView: View {
        @ObservedObject var selectionManager: SelectionManager

        var onSave: () -> Void
        var onLoad: () -> Void
        var onClear: () -> Void
        var onCameraSave: () -> Void
        var onPlayToggled: (Bool) -> Void
        var dirLightCreate: () -> Void
        var pointLightCreate: () -> Void
        var spotLightCreate: () -> Void
        var areaLightCreate: () -> Void

        @State private var isPlaying = false
        @State private var showBuildSettings = false
        @State private var showingNewScriptDialog = false
        @State private var newScriptName = ""

        var body: some View {
            HStack {
                HStack(spacing: 12) {
                    ToolbarButton(iconName: "clear.fill", action: onClear, tooltip: "Clear Scene")
                }
                
                Divider()
                    .frame(height: 24)
                
                // Scripts Section
                HStack(spacing: 8) {
                    Text("Scripts:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        showingNewScriptDialog = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text("New")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.green)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Create New Script")
                    
                    Button(action: {
                        openInXcode()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                            Text("Open in Xcode")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.blue)
                        .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Open Scripts Project in Xcode")
                }

                Spacer() // Push content to the center

                // Centered Buttons
                HStack(spacing: 12) {
                    ToolbarButton(iconName: "square.and.arrow.down", action: onLoad, tooltip: "Import JSON Scene")

                    Button(action: {
                        isPlaying.toggle()
                        onPlayToggled(isPlaying)
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text(isPlaying ? "Pause" : "Play")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(isPlaying ? Color.red : Color.blue)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help(isPlaying ? "Pause Scene" : "Play Scene")

                    ToolbarButton(iconName: "square.and.arrow.up", action: onSave, tooltip: "Export JSON Scene")
                    ToolbarButton(iconName: "camera.fill", action: onCameraSave, tooltip: "Save Camera Transform")
                }

                Spacer()

                // Right-aligned Buttons
                HStack(spacing: 12) {
                    // Build button
                    Button(action: {
                        showBuildSettings = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                            Text("Build")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.green)
                        .cornerRadius(6)
                        .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Build Game Project")
                    
                    Divider()
                        .frame(height: 24)
                    
                    ToolbarButton(iconName: "sun.horizon", action: dirLightCreate, tooltip: "Directional Light")
                    ToolbarButton(iconName: "lightbulb.fill", action: pointLightCreate, tooltip: "Point Light")
                    ToolbarButton(iconName: "lamp.ceiling", action: spotLightCreate, tooltip: "Spot Light")
                    ToolbarButton(iconName: "light.panel.fill", action: areaLightCreate, tooltip: "Area Light")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(
                Color.secondary.opacity(0.1)
                    .ignoresSafeArea()
            )
            .cornerRadius(8)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
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
        }
        
        // MARK: - Script Management Functions
        
        private func createNewScript() {
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
