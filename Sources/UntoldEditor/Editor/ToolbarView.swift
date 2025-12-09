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
    import CodeEditorView
    import LanguageSupport
    import AppKit

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
        var onCreateCube: () -> Void
        var onCreateSphere: () -> Void
        var onCreatePlane: () -> Void
        var onCreateCylinder: () -> Void
        var onCreateCone: () -> Void

        @State private var isPlaying = false
        @State private var showBuildSettings = false
        @State private var showingNewScriptDialog = false
        @State private var newScriptName = ""
        @State private var showingScriptEditor = false

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
            .sheet(isPresented: $showingScriptEditor) {
                ScriptEditorSheet(isPresented: $showingScriptEditor)
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
                // Primitives Section
                Text("Primitives:")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button(action: onCreateCube) {
                    Image(systemName: "cube.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(2)
                .background(Color.gray.opacity(0.8))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .help("Add Cube")

                Button(action: onCreateSphere) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(2)
                .background(Color.gray.opacity(0.8))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .help("Add Sphere")

                Button(action: onCreatePlane) {
                    Image(systemName: "rectangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }
                .padding(2)
                .background(Color.gray.opacity(0.8))
                .cornerRadius(6)
                .buttonStyle(.plain)
                .help("Add Plane")

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

                // Open in-app script editor
                Button(action: { showingScriptEditor = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Script Editor")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.9))
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

    struct ScriptEditorSheet: View {
        @Binding var isPresented: Bool

        @State private var scriptFiles: [URL] = []
        @State private var selectedFile: URL?
        @State private var scriptText: String = ""
        @State private var editPosition: CodeEditor.Position = .init()
        @State private var messages: Set<TextLocated<Message>> = []
        @State private var statusMessage: String?
        @State private var isBuilding = false
        @State private var buildOutput: String = ""
        @State private var keyMonitor: Any?

        @Environment(\.colorScheme) private var colorScheme

        private let manager = ScriptProjectManager.shared

        var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                scriptList
                Divider()
                editorPanel
            }
            Divider()
            buildLog
        }
        .frame(minWidth: 1100, minHeight: 700)
        .onAppear {
            prepareScripts()
            installControlCopyPasteShortcuts()
        }
        .onDisappear {
            removeControlCopyPasteShortcuts()
        }
    }

        private var header: some View {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Script Editor")
                        .font(.headline)
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button("Build Scripts") {
                    runBuild()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding)

                Button("Save") {
                    saveCurrentScript()
                }
                .disabled(selectedFile == nil)

                Button("Close") {
                    isPresented = false
                }
            }
            .padding()
        }

        private var scriptList: some View {
            List(selection: $selectedFile) {
                ForEach(scriptFiles, id: \.self) { url in
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .tag(Optional(url))
                }
            }
            .frame(minWidth: 150, idealWidth: 175, maxWidth: 200, maxHeight: .infinity)
            .onChange(of: selectedFile) { _ in
                loadSelectedScript()
            }
        }

        private var editorPanel: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let selectedFile {
                    Text(selectedFile.lastPathComponent)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    CodeEditor(
                        text: $scriptText,
                        position: $editPosition,
                        messages: $messages,
                        language: .swift()
                    )
                    .environment(
                        \.codeEditorTheme,
                        colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
                } else {
                    VStack {
                        Text("Select a script to edit")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }

        private var buildLog: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Build Output")
                        .font(.subheadline.bold())
                    if isBuilding {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                }
                ScrollView {
                    Text(buildOutput.isEmpty ? "No builds yet." : buildOutput)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .frame(minHeight: 160, maxHeight: 200)
        }

        private func prepareScripts() {
            do {
                if !manager.isProjectInitialized() {
                    try manager.initializeProject()
                }
                statusMessage = nil
            } catch {
                statusMessage = "Failed to initialize scripts: \(error.localizedDescription)"
            }

            reloadScripts()
        }

        private func reloadScripts() {
            scriptFiles = manager.listScriptFiles().sorted { $0.lastPathComponent < $1.lastPathComponent }
            if selectedFile == nil {
                selectedFile = scriptFiles.first
            }
            loadSelectedScript()
        }

        private func loadSelectedScript() {
            guard let selectedFile else {
                scriptText = ""
                return
            }

            do {
                scriptText = try String(contentsOf: selectedFile, encoding: .utf8)
                statusMessage = nil
            } catch {
                scriptText = ""
                statusMessage = "Failed to load \(selectedFile.lastPathComponent)"
            }
        }

        private func saveCurrentScript() {
            guard let selectedFile else { return }

            do {
                try scriptText.write(to: selectedFile, atomically: true, encoding: .utf8)
                statusMessage = "Saved \(selectedFile.lastPathComponent)"
            } catch {
                statusMessage = "Failed to save \(selectedFile.lastPathComponent)"
            }
        }

        private func runBuild() {
            // Ensure current edits are saved before building
            saveCurrentScript()

            isBuilding = true
            buildOutput = "Running swift run...\n"

            manager.buildScripts { result in
                isBuilding = false

                switch result {
                case .success(let output):
                    buildOutput += output
                    statusMessage = "Scripts built successfully"
                case .failure(let error):
                    buildOutput += error.localizedDescription
                    statusMessage = "Build failed"
                }
            }
        }

        // Map Cmd+C/V/X/A to standard copy/paste/cut/select-all while the sheet is active.
        private func installControlCopyPasteShortcuts() {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                guard event.modifierFlags.contains(.command),
                      let character = event.charactersIgnoringModifiers?.lowercased()
                else { return event }

                switch character {
                case "c":
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                    return nil
                case "v":
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return nil
                case "x":
                    NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil)
                    return nil
                case "a":
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return nil
                default:
                    return event
                }
            }
        }

        private func removeControlCopyPasteShortcuts() {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
                keyMonitor = nil
            }
        }
    }
#endif
