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
        
        var rightSection: some View {
            HStack(spacing: 12) {
                Button(action: { showBuildSettings = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "hammer.fill")
                        Text("Build")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)

                Divider().frame(height: 24)
            }
        }

        
        var centeredButtons: some View {
            HStack(spacing: 12) {
                ToolbarButton(iconName: "clear.fill", action: onClear, tooltip: "Clear Scene")

                ToolbarButton(iconName: "square.and.arrow.down", action: onLoad, tooltip: "Import JSON Scene")

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

                ToolbarButton(iconName: "square.and.arrow.up", action: onSave, tooltip: "Export JSON Scene")
            }
        }

        
        var leftSection: some View {
            HStack(spacing: 8) {
                Text("Scripts:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                // New Script
                Button(action: { showingNewScriptDialog = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("New")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.green)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)

                // Open in Xcode
                Button(action: { openInXcode() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer.circle.fill")
                        Text("Open in Xcode")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.blue)
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
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
