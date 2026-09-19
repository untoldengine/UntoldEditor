// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

public struct EditorView: View {
    @State var editor_entities: [EntityID] = getAllGameEntities()
    @StateObject var selectionManager = SelectionManager()
    @StateObject var sceneGraphModel = SceneGraphModel()
    @StateObject var sceneCatalog = ProjectSceneCatalog()
    @ObservedObject var editorBasePath = EditorAssetBasePath.shared
    @State var showUnsavedChangesAlert = false
    @State var unsavedChangesAlertMessage = ""
    @State var assets: [String: [Asset]] = [:]
    @State var selectedAsset: Asset? = nil
    /// Kept here so the Content browser returns to the same folder after the
    /// bottom dock shows another tab (which removes the browser view).
    @StateObject var assetBrowserNavigation = AssetBrowserNavigationState()
    @State var isPlaying = false
    /// True while the play session is paused: the snapshot stays, the engine's
    /// update stops.
    @State var isPaused = false
    /// Captured via `serializeScene()` the instant Play starts; consumed by
    /// `beginPlayModeRestore` on Stop to revert physics/animation/script drift.
    @State var playModeSnapshot: SceneData?
    /// True from Stop-press until the async post-Play restore completes.
    @State var isRestoringPlayMode: Bool = false
    @State var showBlockedDuringPlayAlert = false
    @State var showCreateProject = false
    @ObservedObject var taskCenter = TaskCenter.shared
    @State var rightPanelEnvTab: EnvEffectsTab = .environment
    @State var consoleAutoScroll: Bool = true
    @State var showInvalidProjectAlert = false
    @State var invalidProjectMessage = ""
    @State var showSaveNamePrompt = false
    @State var pendingSceneName: String = "untitled"
    @State var showOverwriteAlert = false
    @State var pendingTargetURL: URL?
    @State var isSaveAs = false
    @State var showSaveBasePathAlert = false
    @State var showSaveFailedAlert = false
    @State var saveFailedMessage = ""
    @State var sceneNameDraft: String = ""
    @FocusState var isSceneNameFieldFocused: Bool
    @State var showSceneRenameFailedAlert = false
    @State var sceneRenameFailedMessage = ""
    @ObservedObject var playbackSettings = EditorPlaybackSettings.shared
    @ObservedObject var dockLayout = EditorDockLayout.shared
    /// Each panel's own filter text, keyed by panel.
    @State var panelSearchText: [PanelID: String] = [:]
    @State var renderPauseGeneration = 0
    let panelAnimationDuration = 0.28
    @State var showWelcomeStart = true
    @State var showCameraControlHints = false
    @State var cameraControlHintsDismissed = false
    @State var showQuickPreviewWarning = false
    @State var quickPreviewEntities: [(EntityID, String)] = []
    @State var sceneAuthoredGameCamera: EntityID?
    @State var pendingQuickPreviewExport: QuickPreviewRuntimeExportRequest?
    @State var isExportingQuickPreviewAsset = false
    @State var quickPreviewConvertOrientation = false
    @State var quickPreviewSourceOrientation = "blender-native"
    @State var quickPreviewCompressGeometry = false
    @State var quickPreviewCompressTextures = false
    @State var quickPreviewAstcencBinPath = ""
    @State var experienceMode: EditorExperienceMode = .explore
    @State var showDemoGallery = true
    @State var showPreviewImportGallery = false
    @State var activeDemoScene: DemoSceneCatalogItem?
    @State var activeDemoCameraFrame: StreamModelCameraFrame?
    @State var activePreviewSceneTitle: String?
    @State var activePreviewImportMode: QuickPreviewImportMode?
    @State var pendingQuickPreviewLoadsInExplore = false
    @State var isViewportDropTargeted = false
    @State var dropStatusMessage: String?
    @State var dropStatusIsError = false
    @ObservedObject var buildTargetSettings = EditorBuildTargetSettings.shared

    var renderer: UntoldRenderer?

    public init() {
        let sharedSelectionManager = SelectionManager()
        _selectionManager = StateObject(wrappedValue: sharedSelectionManager)
        editorController = EditorController(selectionManager: sharedSelectionManager)
        renderer = UntoldRenderer.create(configuration: .editor)
        // Extensions that create pipelines must be registered after the renderer
        // has initialized Metal and loaded the engine shader library.
        registerEditorRenderExtension()
        // Compiles and loads the open project's code components and editor extensions.
        ComponentLibraryController.shared.activate()
        // The working set the frame draws from (View > Splat Debug > Working Set).
        EditorGaussianRuntimeSettings.shared.activate()

        if let r = renderer, let v = renderer?.metalView {
            r.setupCallbacks(gameUpdate: { _ in }, handleInput: r.handleSceneInput)

            InputSystem.shared.setupGestureRecognizers(view: v)
            InputSystem.shared.setupEventMonitors()

            // The render loop pauses while the viewport is resized (live window
            // resize, panel animations); show the frozen frame trimmed, not stretched.
            EditorViewportResizePolicy.apply(to: v)
        }

        // Do not read `isPlaying` here: accessing a @State value inside init
        // (before the view is installed) triggers a SwiftUI runtime warning.
        // The editor always starts in edit mode, matching `isPlaying`'s default.
        gameMode = false
        AnimationSystem.shared.isEnabled = false
    }

    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                editorToolbar
                DockContainerView(
                    layout: dockLayout,
                    registry: dockRegistry,
                    viewportOnly: experienceMode == .explore
                )
                editorStatusBar
            }
            // The toolbar row shares the window's title bar (full-size content view).
            .ignoresSafeArea(.container, edges: .top)
            .background(
                LinearGradient(
                    colors: [Color.editorBackground, Color.editorPanelBackground.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            // A layout change (a panel closed, opened or moved) resizes the
            // viewport; hold the render loop briefly so it stays fluid.
            .onChange(of: dockLayout.state) { _, _ in pauseRenderForPanelAnimation() }

            // Loading indicator overlay
            LoadingIndicatorView()
                .allowsHitTesting(false)
        }
        // Force dark appearance so system controls (tabs, segmented pickers,
        // menus, buttons) render light-on-dark to match the editor theme.
        .preferredColorScheme(.dark)
        .onAppear {
            // Surface engine-side asset loads in the Tasks panel.
            EngineLoadTaskBridge.shared.start()

            EditorUndoManager.shared.onStateRestored = {
                editor_entities = getAllGameEntities()
                selectionManager.objectWillChange.send()
                sceneGraphModel.refreshHierarchy()
            }

            sceneGraphModel.refreshHierarchy()
            sceneCatalog.refresh()
            syncEditorAvailabilityForExperienceMode()

            // `UntoldEditor --open-project <folder>` skips the welcome screen.
            if let launchProject = EditorLaunchOptions.projectToOpen() {
                switchToEditMode()
                showWelcomeStart = false
                openProject(at: launchProject)
            }

            // Listen for asset instance loading completion
            NotificationCenter.default.addObserver(
                forName: .assetInstanceDidLoad,
                object: nil,
                queue: .main
            ) { _ in
                // Refresh hierarchy when async asset instances finish loading
                sceneGraphModel.refreshHierarchy()
            }

            // Listen for project switching to clean up current scene
            NotificationCenter.default.addObserver(
                forName: .projectWillSwitch,
                object: nil,
                queue: .main
            ) { _ in
                cleanupForProjectSwitch()
            }

            // A freshly built component library cannot replace the running one mid-play.
            // Registered here, not as another view modifier: this body is at the limit of
            // what the type checker resolves in reasonable time.
            NotificationCenter.default.addObserver(
                forName: .codeComponentsRequestStopPlay,
                object: nil,
                queue: .main
            ) { _ in
                if isPlaying {
                    setEditorPlayMode(false)
                }
            }

            // The P key and the toolbar share one play toggle, so the key goes
            // through the snapshot flow like the button.
            NotificationCenter.default.addObserver(
                forName: .editorTogglePlay,
                object: nil,
                queue: .main
            ) { _ in
                guard experienceMode == .edit else { return }
                editor_handlePlayToggle(!isPlaying)
            }
        }
        .onChange(of: playbackSettings.useSceneCameraDuringPlay) { _, _ in
            updateActiveCameraForPlayMode()
        }
        // Refresh the hierarchy when entities appear/disappear asynchronously
        // (streaming/tiled assets create their nodes over several frames). The
        // render loop (EditorSceneView.didDraw) detects the change and posts this.
        .onReceive(NotificationCenter.default.publisher(for: .sceneGraphNeedsRefresh)) { _ in
            editor_entities = getAllGameEntities()
            sceneGraphModel.refreshHierarchy()
        }
        // Freeze the viewport while the user drags to resize the window so it
        // doesn't stutter against the live resize; resume when done. The frozen
        // frame is rendered at screen size and trimmed to the window rather than
        // stretched (EditorViewportResizePolicy), so the scene keeps its
        // proportions and growing the window reveals more of it.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willStartLiveResizeNotification)) { note in
            guard let view = renderer?.metalView, let window = view.window, note.object as? NSWindow === window else { return }
            EditorViewportResizePolicy.beginResizeHold(of: view)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification)) { note in
            guard let view = renderer?.metalView, let window = view.window, note.object as? NSWindow === window else { return }
            EditorViewportResizePolicy.endResizeHold(of: view)
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuNew)) { _ in
            showCreateProject = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuOpen)) { _ in
            openExistingProjectFromWelcome()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuNewScene)) { _ in
            guard gameMode == false else {
                showBlockedDuringPlayAlert = true
                return
            }
            requestDestructiveSceneAction(
                { editor_newScene() },
                describing: "creating a new scene",
                showAlert: $showUnsavedChangesAlert,
                alertMessage: $unsavedChangesAlertMessage
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuSaveProject)) { _ in
            editor_saveProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuSave)) { _ in
            editor_handleSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuSaveAs)) { _ in
            editor_handleSaveAs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorMenuReset)) { _ in
            guard gameMode == false else {
                showBlockedDuringPlayAlert = true
                return
            }
            requestDestructiveSceneAction(
                { editor_clearScene() },
                describing: "resetting the scene",
                showAlert: $showUnsavedChangesAlert,
                alertMessage: $unsavedChangesAlertMessage
            )
        }
        .onChange(of: experienceMode) { _, _ in
            syncEditorAvailabilityForExperienceMode()
        }
        // Assets changing on disk (e.g. a scene file deleted from the Asset Browser)
        // need to be reflected in the Scene Hierarchy's separate scene catalog too.
        .onReceive(NotificationCenter.default.publisher(for: .assetBrowserReload)) { _ in
            sceneCatalog.refresh()
        }
        .sheet(isPresented: $showSaveNamePrompt) {
            saveScenePrompt
        }
        .alert("Overwrite Scene?", isPresented: $showOverwriteAlert) {
            Button("Cancel", role: .cancel) {
                showSaveNamePrompt = false
                EditorPendingSwitchAction.shared.cancel()
            }
            Button("Overwrite", role: .destructive) {
                finalizeSceneSave(targetURL: pendingTargetURL, overwrite: true)
            }
        } message: {
            Text("A scene with that name already exists. Overwrite it?")
        }
        .sheet(isPresented: $showCreateProject) {
            CreateProjectView()
        }
        .alert("Invalid Project", isPresented: $showInvalidProjectAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invalidProjectMessage)
        }
        .alert("No Project Loaded", isPresented: $showSaveBasePathAlert) {
            Button("OK", role: .cancel) {
                EditorPendingSwitchAction.shared.cancel()
            }
        } message: {
            Text("Please create a new project or open an existing project before saving scenes.")
        }
        .alert("Save Failed", isPresented: $showSaveFailedAlert) {
            Button("OK", role: .cancel) {
                EditorPendingSwitchAction.shared.cancel()
            }
        } message: {
            Text(saveFailedMessage)
        }
        .alert("Rename Failed", isPresented: $showSceneRenameFailedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(sceneRenameFailedMessage)
        }
        .alert("Quick Preview Entities Cannot Be Saved", isPresented: $showQuickPreviewWarning) {
            Button("Cancel", role: .cancel) {
                quickPreviewEntities = []
                EditorPendingSwitchAction.shared.cancel()
            }
            Button("Delete and Save", role: .destructive) {
                deleteQuickPreviewEntitiesAndSave()
            }
        } message: {
            let entityNames = quickPreviewEntities.map(\.1).joined(separator: ", ")
            let count = quickPreviewEntities.count
            let entityWord = count == 1 ? "entity" : "entities"
            return Text("Your scene contains \(count) Quick Preview \(entityWord):\n\n\(entityNames)\n\nQuick Preview entities use absolute file paths and cannot be saved to scenes. To include these assets permanently, use the Import button in the Asset Browser to copy them into your project first.\n\nYou can delete the Quick Preview entities and save the rest of your scene, or cancel to keep working.")
        }
        .sheet(item: $pendingQuickPreviewExport) { request in
            quickPreviewRuntimeExportSheet(for: request)
        }
        .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
            Button("Cancel", role: .cancel) {
                EditorPendingSwitchAction.shared.cancel()
            }
            Button("Discard Changes", role: .destructive) {
                EditorPendingSwitchAction.shared.consume()
            }
            Button("Save") {
                editor_handleSave()
            }
        } message: {
            Text(unsavedChangesAlertMessage)
        }
        .alert("Stop Play Mode First", isPresented: $showBlockedDuringPlayAlert) {
            Button("OK", role: .cancel) {
                EditorPendingSwitchAction.shared.cancel()
            }
        } message: {
            Text("This action is disabled while Play mode is running. Stop Play mode and try again.")
        }
    }
}
