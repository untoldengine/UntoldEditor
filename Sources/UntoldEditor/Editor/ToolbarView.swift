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
        var onSaveAs: () -> Void
        var onClear: () -> Void
        var onPlayToggled: (Bool) -> Void
        var onShowAssets: () -> Void
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
        @State private var scriptEditorWindow: NSWindow?
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
                Button(action: onShowAssets) {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox.fill")
                        Text("Assets Library")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorSurface)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

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

                // Scripts cluster: primary editor button + overflow menu
                Button(action: {
                    guard ensureAssetBasePath() else { return }
                    toggleScriptEditorWindow()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Script Editor")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.black.opacity(0.9))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.editorAccent)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)

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

        private func toggleScriptEditorWindow() {
            guard ensureAssetBasePath() else { return }
            if let window = scriptEditorWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }

            let editorView = ScriptEditorSheet { self.scriptEditorWindow?.close(); self.scriptEditorWindow = nil }
            let hosting = NSHostingController(rootView: editorView)
            let window = NSWindow(contentViewController: hosting)
            window.title = "Script Editor"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.setContentSize(NSSize(width: 1200, height: 900))
            window.minSize = NSSize(width: 400, height: 300)
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            self.scriptEditorWindow = window
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

    struct ScriptEditorSheet: View {
        var onClose: (() -> Void)?

        @State private var scriptFiles: [URL] = []
        @State private var selectedFile: URL?
        @State private var scriptText: String = ""
        @State private var editPosition: CodeEditor.Position = .init()
        @State private var messages: Set<TextLocated<Message>> = []
        @State private var statusMessage: String?
        @State private var isBuilding = false
        @State private var buildOutput: String = ""
        @State private var keyMonitor: Any?
        @State private var undoStack: [String] = []
        @State private var lastSavedText: String = ""
        @State private var showDeleteConfirm = false
        @State private var pendingSelection: URL?
        @State private var lastKnownSelection: URL?
        @State private var showUnsavedAlert = false
        @State private var pendingClose = false
        @State private var showingNewScriptDialogInSheet = false
        @State private var newScriptNameInSheet = ""
        @Environment(\.colorScheme) private var colorScheme

        private let manager = ScriptProjectManager.shared
        private let uscDocsURL = URL(string: "https://untoldengine.github.io/UntoldEngine/docs/Scripting/usc-scripting-api")!

        private var isDirty: Bool {
            selectedFile != nil && scriptText != lastSavedText
        }

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
        .frame(minWidth: 600, idealWidth: 1100, minHeight: 500, idealHeight: 800)
        .background(Color.editorBackground)
        .accentColor(Color.editorAccent)
        .onAppear {
            prepareScripts()
            installControlCopyPasteShortcuts()
        }
        .onDisappear {
            removeControlCopyPasteShortcuts()
        }
        .interactiveDismissDisabled(isDirty) // Prevent accidental ESC dismissal with unsaved edits (if presented modally elsewhere)
        .alert("Unsaved changes", isPresented: $showUnsavedAlert) {
            Button("Save") {
                saveCurrentScript()
                continuePendingAction()
            }
            Button("Discard", role: .destructive) {
                continuePendingAction()
            }
            Button("Cancel", role: .cancel) {
                cancelPendingAction()
            }
        } message: {
            Text("You have unsaved changes. Do you want to save before continuing?")
        }
        .sheet(isPresented: $showingNewScriptDialogInSheet) {
            NewScriptDialog(
                scriptName: $newScriptNameInSheet,
                onCancel: {
                    showingNewScriptDialogInSheet = false
                    newScriptNameInSheet = ""
                },
                onCreate: {
                    createNewScriptInSheet()
                }
            )
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
                    Link("View Untold Engine API Docs", destination: uscDocsURL)
                        .font(.caption)
                }

                Spacer()

                Button("Build All") {
                    runBuild()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBuilding)

                Button("Save") {
                    saveCurrentScript()
                }
                .disabled(selectedFile == nil)

//                Button("Revert to Saved") {
//                    revertToLastSaved()
//                }
//                .disabled(selectedFile == nil)
//
//                Button("Undo Last Change") {
//                    undoLastChange()
//                }
//                .disabled(undoStack.isEmpty)

//                Button("New Script") {
//                    showingNewScriptDialogInSheet = true
//                }
//                .buttonStyle(.borderedProminent)
//                .tint(.green)

//                Button("Delete") {
//                    showDeleteConfirm = true
//                }
//                .disabled(selectedFile == nil || isProtectedFile(selectedFile))
//                .buttonStyle(.borderedProminent)
//                .tint(.red)
//                .confirmationDialog(
//                    "Delete script?",
//                    isPresented: $showDeleteConfirm,
//                    titleVisibility: .visible
//                ) {
//                    Button("Delete", role: .destructive) {
//                        deleteSelectedScript()
//                    }
//                    Button("Cancel", role: .cancel) { showDeleteConfirm = false }
//                } message: {
//                    if let selectedFile {
//                        Text("Are you sure you want to delete \(selectedFile.lastPathComponent)? This cannot be undone.")
//                    }
//                }

                Button("Close") {
                    if isDirty {
                        pendingClose = true
                        showUnsavedAlert = true
                    } else {
                        onClose?()
                    }
                }
            }
            .padding()
        }

        private var scriptList: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Scripts")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button {
                        showingNewScriptDialogInSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(Color.editorAccent)
                    }
                    .buttonStyle(.plain)
                    .help("New Script")
                    Button {
                        showDeleteConfirm = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedFile == nil || isProtectedFile(selectedFile))
                    .help("Delete Script")
                    .confirmationDialog(
                        "Delete script?",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            deleteSelectedScript()
                        }
                        Button("Cancel", role: .cancel) { showDeleteConfirm = false }
                    } message: {
                        if let selectedFile {
                            Text("Are you sure you want to delete \(selectedFile.lastPathComponent)? This cannot be undone.")
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.editorSurface)

                Divider()
                    .background(Color.editorDivider)

                List(selection: $selectedFile) {
                    ForEach(scriptFiles, id: \.self) { url in
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                            .tag(Optional(url))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .background(Color.editorPanelBackground)
            .cornerRadius(8)
            .frame(minWidth: 180, idealWidth: 220, maxWidth: 260, maxHeight: .infinity)
            .onChange(of: selectedFile) { newSelection in
                handleSelectionChange(newSelection)
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
                    .background(Color.editorSurface)
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
                    Spacer()
                    Button {
                        let output = buildOutput
                        #if os(macOS)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(output, forType: .string)
                        #endif
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Copy build output")
                    .disabled(buildOutput.isEmpty)

                    Button {
                        buildOutput = ""
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear build output")
                    .disabled(buildOutput.isEmpty)
                }
                .padding(.horizontal, 4)

                ScrollViewReader { proxy in
                    ScrollView {
                        Text(buildOutput.isEmpty ? "No builds yet." : buildOutput)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                            .id("buildOutputText")
                            .textSelection(.enabled)
                    }
                    .onChange(of: buildOutput) { _ in
                        withAnimation {
                            proxy.scrollTo("buildOutputText", anchor: .bottom)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .background(Color.editorPanelBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.editorDivider, lineWidth: 1)
            )
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
            lastKnownSelection = selectedFile
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
                lastSavedText = scriptText
                undoStack.removeAll()
            } catch {
                scriptText = ""
                statusMessage = "Failed to load \(selectedFile.lastPathComponent)"
            }
        }

        private func saveCurrentScript() {
            guard let selectedFile else { return }

            do {
                if scriptText != lastSavedText {
                    undoStack.append(lastSavedText)
                }
                try scriptText.write(to: selectedFile, atomically: true, encoding: .utf8)
                statusMessage = "Saved \(selectedFile.lastPathComponent)"
                lastSavedText = scriptText
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

        private func revertToLastSaved() {
            guard selectedFile != nil else { return }
            scriptText = lastSavedText
            statusMessage = "Reverted to last saved."
        }

        private func undoLastChange() {
            guard let previous = undoStack.popLast() else {
                statusMessage = "Nothing to undo."
                return
            }
            scriptText = previous
            statusMessage = "Reverted last change."
        }

        private func deleteSelectedScript() {
            guard let file = selectedFile else { return }
            guard !isProtectedFile(file) else {
                statusMessage = "Cannot delete protected file."
                return
            }
            do {
                try FileManager.default.removeItem(at: file)
                statusMessage = "Deleted \(file.lastPathComponent)"
                showDeleteConfirm = false
                manager.removeScriptInvocationFromMain(name: file.deletingPathExtension().lastPathComponent)
                reloadScripts()
                if scriptFiles.isEmpty {
                    selectedFile = nil
                    scriptText = ""
                } else {
                    selectedFile = scriptFiles.first
                    loadSelectedScript()
                }
            } catch {
                statusMessage = "Failed to delete \(file.lastPathComponent)"
            }
        }

        private func isProtectedFile(_ url: URL?) -> Bool {
            guard let url else { return true }
            return url.lastPathComponent == "GenerateScripts.swift"
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

        private func handleSelectionChange(_ newSelection: URL?) {
            guard let newSelection else { return }

            if isDirty {
                pendingSelection = newSelection
                selectedFile = lastKnownSelection
                showUnsavedAlert = true
                return
            }

            lastKnownSelection = newSelection
            loadSelectedScript()
        }

        private func continuePendingAction() {
            if let target = pendingSelection {
                selectedFile = target
                lastKnownSelection = target
                loadSelectedScript()
            } else if pendingClose {
                onClose?()
            }
            pendingSelection = nil
            pendingClose = false
        }

        private func cancelPendingAction() {
            pendingSelection = nil
            pendingClose = false
        }

        private func createNewScriptInSheet() {
            do {
                try manager.createNewScript(name: newScriptNameInSheet)
                reloadScripts()
                if let created = scriptFiles.first(where: { $0.deletingPathExtension().lastPathComponent == newScriptNameInSheet }) {
                    selectedFile = created
                    lastKnownSelection = created
                    loadSelectedScript()
                }
                statusMessage = "Created \(newScriptNameInSheet).swift"
            } catch {
                statusMessage = "Failed to create script: \(error.localizedDescription)"
            }
            newScriptNameInSheet = ""
            showingNewScriptDialogInSheet = false
        }
    }
#endif
