import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

public struct Asset: Identifiable {
    public let id = UUID()
    public let name: String
    public let category: String
    public let path: URL
    var isFolder: Bool = false
}

private struct CameraControlHintsView: View {
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Camera Controls", systemImage: "video.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Dismiss")
            }

            VStack(alignment: .leading, spacing: 6) {
                Label("Two-finger drag to orbit", systemImage: "arrow.triangle.2.circlepath")
                Label("Scroll or pinch to zoom", systemImage: "magnifyingglass")
                Label("WASD moves, Q/E raises and lowers", systemImage: "keyboard")
            }
            .font(.caption)
            .foregroundColor(.white.opacity(0.82))
            .labelStyle(.titleAndIcon)
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(Color.editorPanelBackground.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
    }
}

public struct EditorView: View {
    @State private var editor_entities: [EntityID] = getAllGameEntities()
    @StateObject private var selectionManager = SelectionManager()
    @StateObject private var sceneGraphModel = SceneGraphModel()
    @ObservedObject private var editorBasePath = EditorAssetBasePath.shared
    @State private var assets: [String: [Asset]] = [:]
    @State private var selectedAsset: Asset? = nil
    @State private var isPlaying = false
    @State private var showCreateProject = false
    @State private var showInvalidProjectAlert = false
    @State private var invalidProjectMessage = ""
    @State private var showSaveNamePrompt = false
    @State private var pendingSceneName: String = "untitled"
    @State private var showOverwriteAlert = false
    @State private var pendingTargetURL: URL?
    @State private var isSaveAs = false
    @State private var showSaveBasePathAlert = false
    @State private var useSceneCameraDuringPlay = false
    @State private var showWelcomeStart = true
    @State private var showCameraControlHints = false
    @State private var cameraControlHintsDismissed = false
    @State private var showQuickPreviewWarning = false
    @State private var quickPreviewEntities: [(EntityID, String)] = []
    @State private var sceneAuthoredGameCamera: EntityID?
    @State private var pendingQuickPreviewExport: QuickPreviewRuntimeExportRequest?
    @State private var isExportingQuickPreviewAsset = false
    @State private var quickPreviewConvertOrientation = false
    @State private var quickPreviewSourceOrientation = "blender-native"
    @State private var quickPreviewCompressGeometry = false
    @State private var quickPreviewCompressTextures = false
    @State private var quickPreviewAstcencBinPath = ""
    @State private var experienceMode: EditorExperienceMode = .explore
    @State private var showDemoGallery = true
    @State private var showPreviewImportGallery = false
    @State private var activeDemoScene: DemoSceneCatalogItem?
    @State private var activeDemoCameraFrame: StreamModelCameraFrame?
    @State private var activePreviewSceneTitle: String?
    @State private var activePreviewImportMode: QuickPreviewImportMode?
    @State private var pendingQuickPreviewLoadsInExplore = false

    var renderer: UntoldRenderer?

    public init() {
        let sharedSelectionManager = SelectionManager()
        _selectionManager = StateObject(wrappedValue: sharedSelectionManager)
        editorController = EditorController(selectionManager: sharedSelectionManager)
        renderer = UntoldRenderer.create(configuration: .editor)
        // Extensions that create pipelines must be registered after the renderer
        // has initialized Metal and loaded the engine shader library.
        registerEditorRenderExtension()

        if let r = renderer, let v = renderer?.metalView {
            r.setupCallbacks(gameUpdate: { _ in }, handleInput: r.handleSceneInput)

            InputSystem.shared.setupGestureRecognizers(view: v)
            InputSystem.shared.setupEventMonitors()
        }

        gameMode = isPlaying
        AnimationSystem.shared.isEnabled = isPlaying
    }

    public var body: some View {
        ZStack {
            VStack {
                if experienceMode == .edit {
                    editorToolbar
                    Divider()
                }
                HStack {
                    if experienceMode == .edit {
                        VStack {
                            SceneHierarchyView(
                                selectionManager: selectionManager,
                                sceneGraphModel: sceneGraphModel,
                                entityList: editor_entities,
                                onAddEntity_Editor: editor_addNewEntity,
                                onRemoveEntity_Editor: editor_removeEntity,
                                onAddCube: editor_createCube,
                                onAddSphere: editor_createSphere,
                                onAddPlane: editor_createPlane,
                                onAddDirLight: editor_createDirLight,
                                onAddPointLight: editor_createPointLight,
                                onAddSpotLight: editor_createSpotLight,
                                onAddAreaLight: editor_createAreaLight,
                                onParentEntity: editor_parentEntity,
                                onUnparentEntity: editor_unparentEntity
                            )
                        }
                    }

                    VStack(spacing: 0) {
                        editorSceneViewport
                        if experienceMode == .edit {
                            TransformManipulationToolbar(controller: editorController!)
                                .frame(height: 40)
                            TabView {
                                AssetBrowserView(
                                    assets: $assets,
                                    selectedAsset: $selectedAsset,
                                    selectionManager: selectionManager,
                                    sceneGraphModel: sceneGraphModel,
                                    editor_addEntityWithAsset: editor_addEntityWithAsset,
                                    editor_loadSceneAuthoredFromAsset: editor_loadSceneAuthoredFromAsset
                                )
                                .tabItem { Label("Assets", systemImage: "shippingbox") }

                                LogConsoleView()
                                    .tabItem { Label("Console", systemImage: "terminal") }
                            }
                            .frame(height: 200)
                            .clipped()
                        }
                    }

                    if experienceMode == .edit {
                        TabView {
                            EnvironmentView(selectedAsset: $selectedAsset)
                                .tabItem {
                                    Label("Environment", systemImage: "sun.max")
                                }

                            PostProcessingEditorView()
                                .tabItem {
                                    Label("Effects", systemImage: "cube")
                                }

                            InspectorView(
                                selectionManager: selectionManager,
                                sceneGraphModel: sceneGraphModel,
                                onAddName_Editor: editor_addName,
                                selectedAsset: $selectedAsset
                            )
                            .tabItem {
                                Label("Inspector", systemImage: "cube")
                            }
                        }
                        .frame(minWidth: 200, maxWidth: 250)
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [Color.editorBackground, Color.editorPanelBackground.opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )

            // Loading indicator overlay
            LoadingIndicatorView()
                .allowsHitTesting(false)
        }
        .onAppear {
            EditorUndoManager.shared.onStateRestored = {
                editor_entities = getAllGameEntities()
                selectionManager.objectWillChange.send()
                sceneGraphModel.refreshHierarchy()
            }

            sceneGraphModel.refreshHierarchy()
            syncEditorAvailabilityForExperienceMode()

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
        }
        .onChange(of: useSceneCameraDuringPlay) { _, _ in
            updateActiveCameraForPlayMode()
        }
        .onChange(of: experienceMode) { _, _ in
            syncEditorAvailabilityForExperienceMode()
        }
        .sheet(isPresented: $showSaveNamePrompt) {
            saveScenePrompt
        }
        .alert("Overwrite Scene?", isPresented: $showOverwriteAlert) {
            Button("Cancel", role: .cancel) {
                showSaveNamePrompt = false
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
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please create a new project or open an existing project before saving scenes.")
        }
        .alert("Quick Preview Entities Cannot Be Saved", isPresented: $showQuickPreviewWarning) {
            Button("Cancel", role: .cancel) {
                quickPreviewEntities = []
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
    }

    private var editorSceneViewport: some View {
        EditorSceneView(renderer: renderer!)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                EngineStatsOverlayView()
            }
            .overlay {
                if shouldShowDemoGallery {
                    DemoGalleryView(
                        demos: demoSceneCatalog,
                        onDemoSelected: editor_loadDemoScene,
                        onTryOwnScene: showPreviewImportChooser,
                        onCreateProject: createProjectFromExplore,
                        onOpenProject: openProjectFromExplore,
                        onOpenFullEditor: switchToEditMode
                    )
                    .padding()
                }
            }
            .overlay {
                if shouldShowPreviewImportGallery {
                    PreviewImportGalleryView(
                        onModeSelected: loadCustomPreviewScene,
                        onBackToDemos: showDemoChooser,
                        onOpenFullEditor: switchToEditMode
                    )
                    .padding()
                }
            }
            .overlay(alignment: .top) {
                if shouldShowExploreSceneOverlay, let activeDemoScene {
                    ExploreSceneOverlayView(
                        demo: activeDemoScene,
                        onChooseAnotherDemo: showDemoChooser,
                        onResetCamera: resetActiveDemoCamera,
                        onOpenFullEditor: switchToEditMode
                    )
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .top) {
                if shouldShowQuickPreviewSceneOverlay, let activePreviewSceneTitle {
                    QuickPreviewSceneOverlayView(
                        title: activePreviewSceneTitle,
                        mode: activePreviewImportMode,
                        onLoadAnother: showPreviewImportChooser,
                        onChooseDemo: showDemoChooser,
                        onOpenFullEditor: switchToEditMode
                    )
                    .padding(.top, 12)
                    .padding(.horizontal, 16)
                }
            }
            .overlay(alignment: .bottom) {
                if shouldShowCameraControlHints {
                    CameraControlHintsView {
                        dismissCameraControlHints()
                    }
                    .padding(.bottom, 14)
                }
            }
    }

    private var editorToolbar: some View {
        ToolbarView(
            selectionManager: selectionManager,
            onSave: editor_handleSave,
            onSaveAs: editor_handleSaveAs,
            onClear: editor_clearScene,
            onPlayToggled: { isPlaying in
                editor_handlePlayToggle(isPlaying)
            },
            useSceneCameraDuringPlay: $useSceneCameraDuringPlay,
            dirLightCreate: editor_createDirLight,
            pointLightCreate: editor_createPointLight,
            spotLightCreate: editor_createSpotLight,
            areaLightCreate: editor_createAreaLight,
            onCreateCube: editor_createCube,
            onCreateSphere: editor_createSphere,
            onCreatePlane: editor_createPlane,
            onCreateCylinder: editor_createCylinder,
            onCreateCone: editor_createCone
        )
    }

    private var saveScenePrompt: some View {
        VStack(spacing: 12) {
            Text("Save Scene")
                .font(.headline)
            Text("Scenes are saved to the Scenes folder in your Asset Folder.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Scene name", text: $pendingSceneName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit { confirmSaveSceneName() }

            HStack {
                Button("Cancel") { showSaveNamePrompt = false }
                Spacer()
                Button("Save") { confirmSaveSceneName() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pendingSceneName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func completeDemoSceneAuthoredLoad(
        _ success: Bool,
        existingEntityIds: Set<EntityID>,
        completion: (Bool) -> Void
    ) {
        guard success else {
            completion(false)
            return
        }

        removeDefaultSceneAuthoredEntities(existingEntityIds: existingEntityIds)
        let importedCamera = findImportedGameCamera(existingEntityIds: existingEntityIds)
        sceneAuthoredGameCamera = importedCamera
        if let importedCamera {
            applyGameCameraFrameToSceneCamera(importedCamera)
        }
        completion(importedCamera != nil)
    }

    private var shouldShowDemoGallery: Bool {
        showWelcomeStart
            && showDemoGallery
            && showPreviewImportGallery == false
            && experienceMode == .explore
            && editorBasePath.basePath == nil
    }

    private var shouldShowPreviewImportGallery: Bool {
        showWelcomeStart
            && showPreviewImportGallery
            && experienceMode == .explore
            && editorBasePath.basePath == nil
    }

    private var shouldShowExploreSceneOverlay: Bool {
        experienceMode == .explore
            && showDemoGallery == false
            && showPreviewImportGallery == false
            && activeDemoScene != nil
    }

    private var shouldShowQuickPreviewSceneOverlay: Bool {
        experienceMode == .explore
            && showDemoGallery == false
            && showPreviewImportGallery == false
            && activePreviewSceneTitle != nil
    }

    private var shouldShowCameraControlHints: Bool {
        showCameraControlHints
            && shouldShowDemoGallery == false
            && (hasQuickPreviewContent() || activeDemoScene != nil)
    }

    private func hasQuickPreviewContent() -> Bool {
        getAllGameEntities().contains { entityId in
            hasComponent(entityId: entityId, componentType: QuickPreviewComponent.self)
        }
    }

    private func revealCameraControlHintsIfNeeded() {
        guard cameraControlHintsDismissed == false else {
            return
        }

        showCameraControlHints = true
    }

    private func dismissCameraControlHints() {
        cameraControlHintsDismissed = true
        showCameraControlHints = false
    }

    private func syncEditorAvailabilityForExperienceMode() {
        editorController?.isEnabled = experienceMode == .edit

        if experienceMode == .explore {
            enableExploreNavigationMode()
            clearExploreSelection()
        } else {
            disableExploreNavigationMode()
        }
    }

    private func switchToEditMode() {
        experienceMode = .edit
        showDemoGallery = false
        showPreviewImportGallery = false
        disableExploreNavigationMode()
    }

    private func createProjectFromExplore() {
        switchToEditMode()
        showWelcomeStart = false
        showCreateProject = true
    }

    private func openProjectFromExplore() {
        switchToEditMode()
        showWelcomeStart = false
        openExistingProjectFromWelcome()
    }

    private func showDemoChooser() {
        experienceMode = .explore
        showDemoGallery = true
        showPreviewImportGallery = false
        activePreviewSceneTitle = nil
        activePreviewImportMode = nil
        showCameraControlHints = false
        enableExploreNavigationMode()
    }

    private func showPreviewImportChooser() {
        experienceMode = .explore
        showWelcomeStart = true
        showDemoGallery = false
        showPreviewImportGallery = true
        activeDemoScene = nil
        activeDemoCameraFrame = nil
        activePreviewSceneTitle = nil
        activePreviewImportMode = nil
        showCameraControlHints = false
        enableExploreNavigationMode()
    }

    private func loadCustomPreviewScene(mode: QuickPreviewImportMode) {
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = nil
        activeDemoCameraFrame = nil
        enableExploreNavigationMode()
        editor_handleQuickPreview(mode: mode, fromExploreMode: true)
    }

    private func resetActiveDemoCamera() {
        guard let activeDemoCameraFrame else {
            return
        }

        applyCameraFrame(activeDemoCameraFrame)
    }

    private func openExistingProjectFromWelcome() {
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

        let fm = FileManager.default
        let projectName = projectURL.lastPathComponent
        let xcodeProjectPath = projectURL.appendingPathComponent("\(projectName).xcodeproj")
        guard fm.fileExists(atPath: xcodeProjectPath.path) else {
            invalidProjectMessage = "This doesn't appear to be a valid UntoldEngine project.\n\nExpected to find: \(projectName).xcodeproj"
            showInvalidProjectAlert = true
            showWelcomeStart = true
            return
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
                return
            }
        }

        let assetFolders = ["Models", "StreamModels", "Animations", "Scenes", "Scripts", "Gaussians", "Materials", "HDR", "Shaders"]
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
    }

    private func editor_handleSave() {
        guard assetBasePath != nil else {
            showSaveBasePathAlert = true
            return
        }

        // Check for Quick Preview entities before saving
        if checkForQuickPreviewEntities() {
            return
        }

        // If we have a current scene path, save immediately
        if let sceneURL = editorController?.currentSceneURL {
            let sceneData: SceneData = serializeScene()
            saveSceneDirect(sceneData: sceneData, to: sceneURL)
            return
        }

        // Otherwise prompt for a name
        isSaveAs = false
        pendingSceneName = "untitled"
        showSaveNamePrompt = true
    }

    private func editor_handleSaveAs() {
        guard assetBasePath != nil else {
            showSaveBasePathAlert = true
            return
        }

        // Check for Quick Preview entities before saving
        if checkForQuickPreviewEntities() {
            return
        }

        isSaveAs = true
        if let current = editorController?.currentSceneURL {
            pendingSceneName = current.deletingPathExtension().lastPathComponent
        } else {
            pendingSceneName = "untitled"
        }
        showSaveNamePrompt = true
    }

    private func confirmSaveSceneName() {
        let name = pendingSceneName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else { return }

        guard let basePath = assetBasePath else {
            showSaveNamePrompt = false
            print("❌ Cannot save scene: Asset Folder not set.")
            return
        }

        let scenesFolder = basePath.appendingPathComponent("Scenes", isDirectory: true)
        try? FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        let targetURL = scenesFolder.appendingPathComponent(name).appendingPathExtension(untoldSceneFileExtension)
        pendingTargetURL = targetURL

        if FileManager.default.fileExists(atPath: targetURL.path) {
            showOverwriteAlert = true
            return
        }

        finalizeSceneSave(targetURL: targetURL, overwrite: false)
    }

    private func finalizeSceneSave(targetURL: URL? = nil, overwrite: Bool = false) {
        let sceneData: SceneData = serializeScene()

        let destinationURL: URL
        if let targetURL {
            destinationURL = targetURL
        } else if let existing = editorController?.currentSceneURL {
            destinationURL = existing
        } else {
            showSaveNamePrompt = true
            return
        }

        if FileManager.default.fileExists(atPath: destinationURL.path), !overwrite {
            showOverwriteAlert = true
            return
        }

        saveSceneDirect(sceneData: sceneData, to: destinationURL)
        editorController?.currentSceneURL = destinationURL
        showSaveNamePrompt = false
        showOverwriteAlert = false
        isSaveAs = false
    }

    private func editor_handleLoad() {
        var sceneData: SceneData?

        // Check if a scene is selected in the Asset Browser
        if let asset = selectedAsset,
           asset.category == "Scenes",
           asset.path.pathExtension.lowercased() == untoldSceneFileExtension
        {
            // Load from selected asset
            sceneData = loadGameScene(from: asset.path)
        } else {
            // Fall back to file picker
            sceneData = loadGameScene()
        }

        if let sceneData {
            destroyAllEntities()
            removeGizmo()
            EditorComponentsState.shared.clear()
            EditorUndoManager.shared.clear()
            sceneAuthoredGameCamera = nil
            deserializeScene(sceneData: sceneData)
            editorController?.currentSceneURL = nil
            editor_entities = getAllGameEntities()
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            gizmoActive = false
            selectionManager.objectWillChange.send()
            sceneGraphModel.refreshHierarchy()

            CameraSystem.shared.activeCamera = findSceneCamera()
        }
    }

    private func editor_clearScene() {
        destroyAllEntities()
        removeGizmo()
        EditorComponentsState.shared.clear()
        EditorUndoManager.shared.clear()
        sceneAuthoredGameCamera = nil

        let light = createEntity()
        setEntityName(entityId: light, name: "Directional Light")
        createDirLight(entityId: light)

        let sceneCamera = findSceneCamera()

        resetCameraToDefaultTransform(entityId: sceneCamera)

        let gameCamera = findGameCamera()

        resetCameraToDefaultTransform(entityId: gameCamera)

        editor_entities = getAllGameEntities()
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        gizmoActive = false
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()

        CameraSystem.shared.activeCamera = sceneCamera
    }

    private func editor_cameraSave() {
        let sceneCameraEntityID = findSceneCamera()

        if sceneCameraEntityID == .invalid {
            return
        }

        let gameCameraEntityID = findEditorGameCamera()

        if gameCameraEntityID == .invalid {
            return
        }

        let eye = getCameraEye(entityId: sceneCameraEntityID)
        let up = getCameraUp(entityId: sceneCameraEntityID)
        let target = getCameraTarget(entityId: sceneCameraEntityID)

        cameraLookAt(entityId: gameCameraEntityID, eye: eye, target: target, up: up)
    }

    private func editor_loadUSDScene() { /*
     guard let url = openFilePicker() else { return }

     let filename = url.deletingPathExtension().lastPathComponent
     let withExtension = url.pathExtension

     loadScene(filename: filename, withExtension: withExtension)
     editor_entities = getAllGameEntities()
     selectionManager.selectedEntity = nil
     activeEntity = .invalid
     selectionManager.objectWillChange.send()

     CameraSystem.shared.activeCamera = findSceneCamera()
                                      */
    }

    private func editor_addNewEntity() {
        removeGizmo()

        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_removeEntity() {
        guard let entityId = selectionManager.selectedEntity else {
            print("No entity is selected.") // Handle case where no entity is selected
            return
        }
        guard isDerivedAssetNode(entityId) == false else {
            print("⚠️ Asset nodes cannot be removed directly")
            return
        }

        destroyEntity(entityId: entityId)

        editor_entities = getAllGameEntities()
        activeEntity = .invalid
        selectionManager.selectedEntity = nil
        removeGizmo()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_addName() {
        guard let entity = selectionManager.selectedEntity else {
            print("No entity is selected.") // Handle case where no entity is selected
            return
        }

        setEntityName(entityId: entity, name: getEntityName(entityId: entity))
    }

    private func editor_handlePlayToggle(_ isPlaying: Bool) {
        setEditorPlayMode(isPlaying)
    }

    private func setEditorPlayMode(_ shouldPlay: Bool) {
        let didChangePlayState = isPlaying != shouldPlay || gameMode != shouldPlay
        isPlaying = shouldPlay
        gameMode = shouldPlay
        updateActiveCameraForPlayMode()
        AnimationSystem.shared.isEnabled = shouldPlay
        guard didChangePlayState else {
            return
        }

        // Start/stop USC System
        if shouldPlay {
            USCSystem.shared.startPlayMode()
        } else {
            USCSystem.shared.stopPlayMode()
        }
    }

    private func enableExploreNavigationMode() {
        useSceneCameraDuringPlay = true
        setEditorPlayMode(true)
        CameraSystem.shared.activeCamera = findSceneCamera()
    }

    private func disableExploreNavigationMode() {
        if isPlaying {
            setEditorPlayMode(false)
        }
    }

    private func updateActiveCameraForPlayMode() {
        if gameMode {
            CameraSystem.shared.activeCamera = useSceneCameraDuringPlay ? findSceneCamera() : findEditorGameCamera()
        } else {
            CameraSystem.shared.activeCamera = findSceneCamera()
        }
    }

    private func editor_createDirLight() {
        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        createDirLight(entityId: entityId)
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_createPointLight() {
        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        createPointLight(entityId: entityId)
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_createSpotLight() {
        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        createSpotLight(entityId: entityId)
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_createAreaLight() {
        let entityId = createEntity()

        let name = generateEntityName()
        setEntityName(entityId: entityId, name: name)
        registerTransformComponent(entityId: entityId)
        registerSceneGraphComponent(entityId: entityId)

        createAreaLight(entityId: entityId)
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_addEntityWithAsset() {
        editor_addNewEntity()

        let filename = selectedAsset?.path.deletingPathExtension().lastPathComponent
        let withExtension = selectedAsset?.path.pathExtension

        guard let entityId = selectionManager.selectedEntity,
              let fname = filename,
              let ext = withExtension else { return }

        setEntityMeshAsync(entityId: entityId, filename: fname, withExtension: ext) { success in
            if success {
                print("✅ Asset loaded: \(fname).\(ext)")
            } else {
                print("⚠️ Failed to load asset, using fallback: \(fname).\(ext)")
            }
        }

        guard let camera = CameraSystem.shared.activeCamera, let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)

        forward *= -1.0

        let camPosition = cameraComponent.localPosition

        let spawnPosition = camPosition + forward * spawnDistance

        translateTo(entityId: selectionManager.selectedEntity!, position: spawnPosition)
    }

    // MARK: - Primitive Creation Functions

    private func editor_createPrimitive(name: String, meshes: [Mesh]) {
        removeGizmo()

        let entityId = createEntity()
        // Append entity ID to make the name unique
        let uniqueName = "\(name)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        // Use setEntityMeshDirect which follows the same pattern as setEntityMesh
        setEntityMeshDirect(entityId: entityId, meshes: meshes, assetName: name)

        // Spawn in front of camera
        guard let camera = CameraSystem.shared.activeCamera, let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: simd_float3(0.0, 0.0, 0.0))

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
    }

    private func editor_createCube() {
        let meshes = BasicPrimitives.createCube()
        editor_createPrimitive(name: "Cube", meshes: meshes)
    }

    private func editor_createSphere() {
        let meshes = BasicPrimitives.createSphere()
        editor_createPrimitive(name: "Sphere", meshes: meshes)
    }

    private func editor_createPlane() {
        let meshes = BasicPrimitives.createPlane()
        editor_createPrimitive(name: "Plane", meshes: meshes)
    }

    private func editor_createCylinder() {
        let meshes = BasicPrimitives.createCylinder()
        editor_createPrimitive(name: "Cylinder", meshes: meshes)
    }

    private func editor_createCone() {
        let meshes = BasicPrimitives.createCone()
        editor_createPrimitive(name: "Cone", meshes: meshes)
    }

    // MARK: - Parenting Functions

    private func editor_parentEntity(childId: EntityID, parentId: EntityID) {
        guard isDerivedAssetNode(childId) == false, isDerivedAssetNode(parentId) == false else {
            print("⚠️ Asset nodes cannot be reparented directly")
            return
        }

        // Ensure both entities exist and have ScenegraphComponent
        guard hasComponent(entityId: childId, componentType: ScenegraphComponent.self),
              hasComponent(entityId: parentId, componentType: ScenegraphComponent.self)
        else {
            print("⚠️ Cannot parent entity: missing ScenegraphComponent")
            return
        }

        // Ensure child has LocalTransformComponent
        guard hasComponent(entityId: childId, componentType: LocalTransformComponent.self) else {
            print("⚠️ Cannot parent entity: child missing LocalTransformComponent")
            return
        }

        // Ensure parent has LocalTransformComponent and WorldTransformComponent
        guard hasComponent(entityId: parentId, componentType: LocalTransformComponent.self),
              hasComponent(entityId: parentId, componentType: WorldTransformComponent.self)
        else {
            print("⚠️ Cannot parent entity: parent missing transform components")
            return
        }

        // Use the engine's setParent function
        setParent(childId: childId, parentId: parentId, offset: simd_float3(0, 0, 0))

        // Refresh the scene hierarchy to reflect the change
        sceneGraphModel.refreshHierarchy()

        print("✅ Parented entity \(childId) to \(parentId)")
    }

    private func editor_unparentEntity(childId: EntityID) {
        guard isDerivedAssetNode(childId) == false else {
            print("⚠️ Asset nodes cannot be unparented directly")
            return
        }

        // Ensure entity has ScenegraphComponent
        guard hasComponent(entityId: childId, componentType: ScenegraphComponent.self) else {
            print("⚠️ Cannot unparent entity: missing ScenegraphComponent")
            return
        }

        // Ensure entity has LocalTransformComponent
        guard hasComponent(entityId: childId, componentType: LocalTransformComponent.self) else {
            print("⚠️ Cannot unparent entity: missing LocalTransformComponent")
            return
        }

        // Ensure entity has WorldTransformComponent
        guard hasComponent(entityId: childId, componentType: WorldTransformComponent.self) else {
            print("⚠️ Cannot unparent entity: missing WorldTransformComponent")
            return
        }

        // Check if entity actually has a parent
        guard let _ = getEntityParent(entityId: childId) else {
            print("⚠️ Entity has no parent to remove")
            return
        }

        // Use the engine's removeParent function
        removeParent(childId: childId)

        // Refresh the scene hierarchy to reflect the change
        sceneGraphModel.refreshHierarchy()

        print("✅ Unparented entity \(childId)")
    }

    // MARK: - Quick Preview

    private func editor_loadDemoScene(_ demo: DemoSceneCatalogItem) {
        guard let sourceURL = demo.source.resolvedURL else {
            Logger.log(message: "⚠️ Demo source not found: \(demo.title)")
            showDemoGallery = true
            return
        }

        experienceMode = .explore
        showWelcomeStart = true
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = demo
        activeDemoCameraFrame = demo.cameraFrame
        activePreviewSceneTitle = nil
        activePreviewImportMode = nil
        enableExploreNavigationMode()

        deleteExistingQuickPreviewEntities()
        clearSceneBatches()
        removeGizmo()
        clearExploreSelection()

        switch demo.source {
        case .remoteManifest, .bundledManifest:
            loadDemoStreamScene(demo, manifestURL: sourceURL)
        case .bundledAsset:
            loadDemoRuntimeAsset(demo, assetURL: sourceURL)
        }
    }

    private func loadDemoStreamScene(_ demo: DemoSceneCatalogItem, manifestURL: URL) {
        let existingEntityIds = Set(getAllGameEntities())
        let entityId = createDemoPreviewEntity(
            title: demo.title,
            sourceURL: manifestURL,
            fileExtension: "json"
        )

        GeometryStreamingSystem.shared.enabled = true

        setEntityStreamScene(entityId: entityId, url: manifestURL) { success in
            DispatchQueue.main.async {
                guard success else {
                    Logger.log(message: "⚠️ Failed to load demo scene: \(demo.title)")
                    showDemoGallery = true
                    return
                }

                loadDemoSceneAuthoredIfNeeded(
                    demo,
                    url: manifestURL,
                    isRuntimeAsset: false,
                    existingEntityIds: existingEntityIds
                ) { didApplyAuthoredCamera in
                    completeDemoSceneLoad(demo, didApplyAuthoredCamera: didApplyAuthoredCamera)
                }
            }
        }
    }

    private func loadDemoRuntimeAsset(_ demo: DemoSceneCatalogItem, assetURL: URL) {
        let existingEntityIds = Set(getAllGameEntities())
        let fileExtension = demo.source.fileExtension
        let entityId = createDemoPreviewEntity(
            title: demo.title,
            sourceURL: assetURL,
            fileExtension: fileExtension
        )

        GeometryStreamingSystem.shared.enabled = false

        setEntityMeshAsync(entityId: entityId, filename: assetURL.path, withExtension: fileExtension) { success in
            DispatchQueue.main.async {
                guard success else {
                    Logger.log(message: "⚠️ Failed to load demo asset: \(demo.title)")
                    showDemoGallery = true
                    return
                }

                loadDemoSceneAuthoredIfNeeded(
                    demo,
                    url: assetURL,
                    isRuntimeAsset: true,
                    existingEntityIds: existingEntityIds
                ) { didApplyAuthoredCamera in
                    completeDemoSceneLoad(demo, didApplyAuthoredCamera: didApplyAuthoredCamera)
                }
            }
        }
    }

    private func createDemoPreviewEntity(title: String, sourceURL: URL, fileExtension: String) -> EntityID {
        let entityId = createEntity()
        setEntityName(entityId: entityId, name: "Demo-\(title)-\(entityId)")

        if let quickPreviewComp = scene.assign(to: entityId, component: QuickPreviewComponent.self) {
            quickPreviewComp.absoluteFilePath = sourceURL.isFileURL ? sourceURL.path : sourceURL.absoluteString
            quickPreviewComp.fileExtension = fileExtension
            quickPreviewComp.originalFileName = title
        }

        return entityId
    }

    private func loadDemoSceneAuthoredIfNeeded(
        _ demo: DemoSceneCatalogItem,
        url: URL,
        isRuntimeAsset: Bool,
        existingEntityIds: Set<EntityID>,
        completion: @escaping (Bool) -> Void
    ) {
        guard demo.loadsSceneAuthoredPayload else {
            completion(false)
            return
        }

        if isRuntimeAsset {
            loadSceneAuthored(filename: url.path, withExtension: url.pathExtension.lowercased()) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        } else {
            loadSceneAuthored(url: url) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        }
    }

    private func completeDemoSceneLoad(_ demo: DemoSceneCatalogItem, didApplyAuthoredCamera: Bool) {
        if didApplyAuthoredCamera == false, let frame = demo.cameraFrame {
            applyCameraFrame(frame)
        }

        clearExploreSelection()
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        enableExploreNavigationMode()
        revealCameraControlHintsIfNeeded()

        Logger.log(message: "✅ Demo loaded: \(demo.title)")
    }

    private func clearExploreSelection() {
        removeGizmo()
        activeEntity = .invalid
        gizmoActive = false
        selectionManager.selectedEntity = nil
        selectionManager.inspectedMesh = nil
        selectionManager.objectWillChange.send()
    }

    private func applyCameraFrame(_ frame: StreamModelCameraFrame) {
        let camera = findSceneCamera()

        cameraLookAt(entityId: camera, eye: frame.eye, target: frame.target, up: cameraUpDefault)
        CameraSystem.shared.activeCamera = camera

        if frame.usesOriginOrbit {
            let radius = simd_length(frame.eye - frame.target)
            if radius > 0.001 {
                setOrbitOffset(entityId: camera, uTargetOffset: radius)
            }
        } else {
            setOrbitOffset(entityId: camera, uTargetOffset: 25.0)
        }
    }

    private func applyGameCameraFrameToSceneCamera(_ gameCamera: EntityID) {
        let sceneCamera = findSceneCamera()
        let eye = getCameraEye(entityId: gameCamera)
        let up = getCameraUp(entityId: gameCamera)
        let target = getCameraTarget(entityId: gameCamera)

        cameraLookAt(entityId: sceneCamera, eye: eye, target: target, up: up)
        CameraSystem.shared.activeCamera = sceneCamera
    }

    private func findEditorGameCamera() -> EntityID {
        let entities = getAllGameEntities()

        if let sceneAuthoredGameCamera,
           entities.contains(sceneAuthoredGameCamera),
           isGameCamera(sceneAuthoredGameCamera)
        {
            return sceneAuthoredGameCamera
        }

        if let activeCamera = CameraSystem.shared.activeCamera,
           entities.contains(activeCamera),
           isGameCamera(activeCamera)
        {
            return activeCamera
        }

        if let existingGameCamera = entities.first(where: isGameCamera) {
            return existingGameCamera
        }

        return findGameCamera()
    }

    private func isGameCamera(_ entityId: EntityID) -> Bool {
        hasComponent(entityId: entityId, componentType: CameraComponent.self)
            && hasComponent(entityId: entityId, componentType: SceneCameraComponent.self) == false
    }

    private func refreshEditorAfterSceneAuthoredLoad(
        selecting entityId: EntityID?,
        gameCamera: EntityID?
    ) {
        removeGizmo()
        activeEntity = .invalid
        gizmoActive = false
        sceneAuthoredGameCamera = gameCamera
        if let entityId {
            selectionManager.selectedEntity = entityId
        }
        selectionManager.inspectedMesh = nil
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        updateActiveCameraForPlayMode()
        selectionManager.objectWillChange.send()
    }

    private func removeDefaultSceneAuthoredEntities(existingEntityIds: Set<EntityID>) {
        let entities = Set(getAllGameEntities())
        let previousSceneAuthoredGameCamera = sceneAuthoredGameCamera
        sceneAuthoredGameCamera = nil

        let gameCamerasToRemove = existingEntityIds.filter {
            entities.contains($0)
                && isGameCamera($0)
                && (getEntityName(entityId: $0) == "Game Camera" || $0 == previousSceneAuthoredGameCamera)
        }

        for gameCameraId in gameCamerasToRemove {
            destroyEntity(entityId: gameCameraId)
            setCamera(.active(.invalid))
        }

        if let directionalLightId = existingEntityIds.first(where: {
            entities.contains($0)
                && getEntityName(entityId: $0) == "Directional Light"
                && hasComponent(entityId: $0, componentType: DirectionalLightComponent.self)
        }) {
            destroyEntity(entityId: directionalLightId)
        }

        sceneGraphModel.refreshHierarchy()
    }

    private func findImportedGameCamera(existingEntityIds: Set<EntityID>) -> EntityID? {
        getAllGameEntities().first {
            existingEntityIds.contains($0) == false
                && isGameCamera($0)
        }
    }

    private func loadSceneAuthoredPayload(
        filename: String,
        withExtension fileExtension: String,
        selecting entityId: EntityID?,
        sourceName: String
    ) {
        let existingEntityIds = Set(getAllGameEntities())

        loadSceneAuthored(filename: filename, withExtension: fileExtension) { success in
            DispatchQueue.main.async {
                if success {
                    removeDefaultSceneAuthoredEntities(existingEntityIds: existingEntityIds)
                    let importedCamera = findImportedGameCamera(existingEntityIds: existingEntityIds)
                    refreshEditorAfterSceneAuthoredLoad(selecting: entityId, gameCamera: importedCamera)
                    print("✅ Scene-authored cameras/lights loaded: \(sourceName)")
                } else {
                    print("⚠️ Failed to load scene-authored cameras/lights: \(sourceName)")
                }
            }
        }
    }

    private func loadSceneAuthoredPayload(
        url manifestURL: URL,
        selecting entityId: EntityID?,
        sourceName: String
    ) {
        let existingEntityIds = Set(getAllGameEntities())

        loadSceneAuthored(url: manifestURL) { success in
            DispatchQueue.main.async {
                if success {
                    removeDefaultSceneAuthoredEntities(existingEntityIds: existingEntityIds)
                    let importedCamera = findImportedGameCamera(existingEntityIds: existingEntityIds)
                    refreshEditorAfterSceneAuthoredLoad(selecting: entityId, gameCamera: importedCamera)
                    print("✅ Scene-authored cameras/lights loaded: \(sourceName)")
                } else {
                    print("⚠️ Failed to load scene-authored cameras/lights: \(sourceName)")
                }
            }
        }
    }

    private func editor_loadSceneAuthoredFromAsset(_ asset: Asset) {
        let fileExtension = asset.path.pathExtension.lowercased()

        if fileExtension == "untold" {
            loadSceneAuthoredPayload(
                filename: asset.path.path,
                withExtension: fileExtension,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        if fileExtension == "json", isTiledSceneManifest(asset.path) {
            loadSceneAuthoredPayload(
                url: asset.path,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        if fileExtension == "remotestream",
           let urlString = try? String(contentsOf: asset.path, encoding: .utf8),
           let manifestURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            loadSceneAuthoredPayload(
                url: manifestURL,
                selecting: selectionManager.selectedEntity,
                sourceName: asset.name
            )
            return
        }

        print("⚠️ Scene-authored loading is only supported for .untold assets and tiled scene manifests")
    }

    private func editor_handleQuickPreview(mode: QuickPreviewImportMode, fromExploreMode: Bool = false) {
        let openPanel = NSOpenPanel()
        openPanel.title = mode.filePickerTitle
        openPanel.allowedContentTypes = mode.allowedContentTypes
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.message = mode.filePickerMessage

        guard openPanel.runModal() == .OK, let fileURL = openPanel.url else {
            if fromExploreMode {
                showPreviewImportGallery = true
            }
            return
        }

        let fileExtension = fileURL.pathExtension.lowercased()
        let absolutePath = fileURL.path
        let fileName = fileURL.deletingPathExtension().lastPathComponent
        pendingQuickPreviewLoadsInExplore = fromExploreMode

        if isUSDSourceAsset(fileURL) {
            queueQuickPreviewRuntimeExport(sourceURL: fileURL)
            return
        }

        if fileExtension == "json", !isTiledSceneManifest(fileURL) {
            Logger.log(message: "⚠️ Quick Preview JSON is not a tiled scene manifest: \(fileURL.lastPathComponent)")
            if fromExploreMode {
                showPreviewImportGallery = true
                pendingQuickPreviewLoadsInExplore = false
            }
            return
        }

        deleteExistingQuickPreviewEntities()
        let existingEntityIds = Set(getAllGameEntities())

        // Create a new entity for the preview
        removeGizmo()
        let entityId = createEntity()

        let uniqueName = "QuickPreview-\(fileName)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        // Mark this entity as a Quick Preview entity (cannot be saved)
        if let quickPreviewComp = scene.assign(to: entityId, component: QuickPreviewComponent.self) {
            quickPreviewComp.absoluteFilePath = absolutePath
            quickPreviewComp.fileExtension = fileExtension
            quickPreviewComp.originalFileName = fileName
        }

        if fileExtension == "untold" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            // Load Untold runtime asset using absolute path
            setEntityMeshAsync(entityId: entityId, filename: absolutePath, withExtension: fileExtension) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: fileURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: true,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if fromExploreMode {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
                            } else {
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview loaded: \(fileName).\(fileExtension)")
                    } else {
                        print("⚠️ Failed to load Quick Preview, using fallback: \(fileName).\(fileExtension)")
                        if fromExploreMode {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                }
            }
        } else if fileExtension == "ply" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            // Load Gaussian PLY using absolute path
            setEntityGaussian(entityId: entityId, filename: absolutePath, withExtension: fileExtension)
            if fromExploreMode == false {
                revealCameraControlHintsIfNeeded()
            }
            print("✅ Quick Preview Gaussian loaded: \(fileName).\(fileExtension)")
        } else if fileExtension == "json" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = true

            setEntityStreamScene(entityId: entityId, url: fileURL) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: fileURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: false,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if fromExploreMode {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
                            } else {
                                revealCameraControlHintsIfNeeded()
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview stream model loaded: \(fileName).\(fileExtension)")
                    } else {
                        print("⚠️ Failed to load Quick Preview stream model: \(fileName).\(fileExtension)")
                        if fromExploreMode {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                    sceneGraphModel.refreshHierarchy()
                }
            }

            selectionManager.selectedEntity = entityId
            editor_entities = getAllGameEntities()
            sceneGraphModel.refreshHierarchy()

            print("ℹ️ Quick Preview mode: Stream model loaded with absolute manifest path")
            print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
            return
        }

        // Spawn in front of camera
        guard let camera = CameraSystem.shared.activeCamera,
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera)
        else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: spawnPosition)

        // Select and refresh
        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        if fromExploreMode, fileExtension != "untold" {
            completeExploreQuickPreviewLoad(fileName: fileName, mode: mode)
        }

        print("ℹ️ Quick Preview mode: File loaded with absolute path")
        print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
    }

    private func loadQuickPreviewSceneAuthored(
        url: URL,
        fileExtension: String,
        isRuntimeAsset: Bool,
        existingEntityIds: Set<EntityID>,
        completion: @escaping (Bool) -> Void
    ) {
        guard fileExtension == "untold" || fileExtension == "json" else {
            completion(false)
            return
        }

        if isRuntimeAsset {
            loadSceneAuthored(filename: url.path, withExtension: fileExtension) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        } else {
            loadSceneAuthored(url: url) { success in
                DispatchQueue.main.async {
                    completeDemoSceneAuthoredLoad(success, existingEntityIds: existingEntityIds, completion: completion)
                }
            }
        }
    }

    private func isUSDSourceAsset(_ url: URL) -> Bool {
        ["usd", "usda", "usdc", "usdz"].contains(url.pathExtension.lowercased())
    }

    private func queueQuickPreviewRuntimeExport(sourceURL: URL) {
        let cacheDirectory = QuickPreviewRuntimeExportCache.cacheDirectory(for: sourceURL)
        let outputURL = QuickPreviewRuntimeExportCache.outputURL(for: sourceURL, in: cacheDirectory)

        QuickPreviewRuntimeExportCache.pruneStaleCaches(preserving: [cacheDirectory])

        pendingQuickPreviewExport = QuickPreviewRuntimeExportRequest(
            sourceURL: sourceURL,
            outputURL: outputURL
        )
    }

    private func quickPreviewRuntimeExportSheet(for request: QuickPreviewRuntimeExportRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Convert to Untold Preview Asset")
                .font(.title2)
                .bold()

            Text("This USD file needs to be converted to Untold Engine's .untold runtime format before it can be previewed.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Source")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(request.sourceURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)

                Text("Output")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 6)
                Text(request.outputURL.path)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Convert orientation", isOn: $quickPreviewConvertOrientation)

                Picker("Source orientation", selection: $quickPreviewSourceOrientation) {
                    Text("Blender native").tag("blender-native")
                    Text("Engine oriented").tag("engine-oriented")
                }
                .disabled(!quickPreviewConvertOrientation)

                Toggle("Compress geometry (LZ4)", isOn: $quickPreviewCompressGeometry)
                    .help("Compresses vertex and index data with LZ4. Requires the Python lz4 package.")
                if quickPreviewCompressGeometry {
                    Text("Requires: pip install lz4")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }

                Toggle("Compress textures (ASTC)", isOn: $quickPreviewCompressTextures)
                    .help("Converts textures to GPU-native ASTC format. Requires astcenc and the Python Pillow package.")
                if quickPreviewCompressTextures {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Link("Install astcenc ->", destination: URL(string: "https://github.com/ARM-software/astc-encoder/releases")!)
                                .font(.caption)
                            Text("-")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Also requires: pip install Pillow")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("astcenc path (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            HStack {
                                TextField("/opt/homebrew/bin/astcenc", text: $quickPreviewAstcencBinPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                Button("Browse...") {
                                    let panel = NSOpenPanel()
                                    panel.canChooseFiles = true
                                    panel.canChooseDirectories = false
                                    panel.allowsMultipleSelection = false
                                    panel.title = "Select astcenc binary"
                                    if panel.runModal() == .OK, let url = panel.url {
                                        quickPreviewAstcencBinPath = url.path
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 20)
                }
            }

            if isExportingQuickPreviewAsset {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Exporting...")
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingQuickPreviewExport = nil
                }
                .disabled(isExportingQuickPreviewAsset)

                Button("Export and Load") {
                    exportAndLoadQuickPreviewRuntimeAsset(request)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExportingQuickPreviewAsset)
            }
        }
        .padding(20)
        .frame(width: 560)
    }

    private func exportAndLoadQuickPreviewRuntimeAsset(_ request: QuickPreviewRuntimeExportRequest) {
        guard !isExportingQuickPreviewAsset else { return }
        guard let exporterScript = findExportUntoldScript() else {
            Logger.log(message: "❌ export-untold script not found. Expected at .build/checkouts/UntoldEngine/scripts/export-untold")
            pendingQuickPreviewExport = nil
            return
        }

        isExportingQuickPreviewAsset = true
        let convertOrientation = quickPreviewConvertOrientation
        let sourceOrientation = quickPreviewSourceOrientation
        let compressGeometry = quickPreviewCompressGeometry
        let compressTextures = quickPreviewCompressTextures
        let astcencBin = quickPreviewAstcencBinPath.trimmingCharacters(in: .whitespacesAndNewlines)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let tempDirectory = FileManager.default.temporaryDirectory
            let outputLogURL = tempDirectory.appendingPathComponent("quick-preview-export-\(UUID().uuidString).out")
            let errorLogURL = tempDirectory.appendingPathComponent("quick-preview-export-\(UUID().uuidString).err")

            do {
                try FileManager.default.createDirectory(at: request.outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: request.outputURL.path) {
                    try FileManager.default.removeItem(at: request.outputURL)
                }
                FileManager.default.createFile(atPath: outputLogURL.path, contents: nil)
                FileManager.default.createFile(atPath: errorLogURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputLogURL)
                let errorHandle = try FileHandle(forWritingTo: errorLogURL)
                defer {
                    try? outputHandle.close()
                    try? errorHandle.close()
                    try? FileManager.default.removeItem(at: outputLogURL)
                    try? FileManager.default.removeItem(at: errorLogURL)
                }

                process.executableURL = exporterScript
                var arguments = [
                    "--input", request.sourceURL.path,
                    "--output", request.outputURL.path,
                ]
                if convertOrientation {
                    arguments.append("--ConvertOrientation")
                    arguments.append(contentsOf: ["--source-orientation", sourceOrientation])
                }
                if compressGeometry {
                    arguments.append("--compress-geometry")
                }
                process.arguments = arguments
                process.standardOutput = outputHandle
                process.standardError = errorHandle

                try process.run()
                process.waitUntilExit()

                let stdout = (try? String(contentsOf: outputLogURL, encoding: .utf8)) ?? ""
                let stderr = (try? String(contentsOf: errorLogURL, encoding: .utf8)) ?? ""
                let exportSucceeded = process.terminationStatus == 0

                DispatchQueue.main.async {
                    if !stdout.isEmpty { Logger.log(message: stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    if !stderr.isEmpty { Logger.log(message: stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
                }

                if exportSucceeded, compressTextures {
                    let texturesDir = request.outputURL.deletingLastPathComponent().appendingPathComponent("Textures")
                    if FileManager.default.fileExists(atPath: texturesDir.path),
                       let texbakeScript = findTexbakeScript()
                    {
                        let bakeResult = runTexbakeStep(script: texbakeScript, arguments: ["--dir", texturesDir.path], astcencBin: astcencBin)
                        let patchResult = runTexbakeStep(script: texbakeScript, arguments: ["--patch-refs", request.outputURL.path], astcencBin: astcencBin)
                        DispatchQueue.main.async {
                            if !bakeResult.stdout.isEmpty { Logger.log(message: bakeResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            if !bakeResult.stderr.isEmpty { Logger.log(message: bakeResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            if !patchResult.stdout.isEmpty { Logger.log(message: patchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            if !patchResult.stderr.isEmpty { Logger.log(message: patchResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)) }
                            if bakeResult.status != 0 || patchResult.status != 0 {
                                Logger.log(message: "⚠️ ASTC compression had errors — preview asset exported without compressed textures")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Logger.log(message: "⚠️ ASTC skipped — texbake.py not found or no Textures folder present")
                        }
                    }
                }

                DispatchQueue.main.async {
                    isExportingQuickPreviewAsset = false
                    pendingQuickPreviewExport = nil
                    if exportSucceeded {
                        editor_loadQuickPreviewAsset(from: request.outputURL, originalSourceURL: request.sourceURL)
                    } else {
                        QuickPreviewRuntimeExportCache.removeCacheDirectory(at: request.outputURL.deletingLastPathComponent())
                        Logger.log(message: "❌ Quick Preview export failed for \(request.sourceURL.lastPathComponent)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isExportingQuickPreviewAsset = false
                    pendingQuickPreviewExport = nil
                    QuickPreviewRuntimeExportCache.removeCacheDirectory(at: request.outputURL.deletingLastPathComponent())
                    Logger.log(message: "❌ Quick Preview export failed: \(error)")
                }
            }
        }
    }

    private func editor_loadQuickPreviewAsset(from loadURL: URL, originalSourceURL: URL? = nil) {
        let sourceURL = originalSourceURL ?? loadURL
        let fileExtension = loadURL.pathExtension.lowercased()
        let absolutePath = loadURL.path
        let fileName = sourceURL.deletingPathExtension().lastPathComponent

        deleteExistingQuickPreviewEntities()
        let existingEntityIds = Set(getAllGameEntities())
        removeGizmo()

        let entityId = createEntity()
        let uniqueName = "QuickPreview-\(fileName)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        if let quickPreviewComp = scene.assign(to: entityId, component: QuickPreviewComponent.self) {
            quickPreviewComp.absoluteFilePath = sourceURL.path
            quickPreviewComp.fileExtension = sourceURL.pathExtension.lowercased()
            quickPreviewComp.originalFileName = fileName
            if originalSourceURL != nil {
                quickPreviewComp.runtimePreviewDirectoryPath = loadURL.deletingLastPathComponent().path
            }
        }

        if fileExtension == "untold" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            setEntityMeshAsync(entityId: entityId, filename: absolutePath, withExtension: fileExtension) { success in
                DispatchQueue.main.async {
                    if success {
                        loadQuickPreviewSceneAuthored(
                            url: loadURL,
                            fileExtension: fileExtension,
                            isRuntimeAsset: true,
                            existingEntityIds: existingEntityIds
                        ) { _ in
                            if pendingQuickPreviewLoadsInExplore {
                                completeExploreQuickPreviewLoad(fileName: fileName, mode: .untoldAsset)
                            } else {
                                sceneGraphModel.refreshHierarchy()
                            }
                        }
                        print("✅ Quick Preview loaded: \(loadURL.lastPathComponent)")
                    } else {
                        print("⚠️ Failed to load Quick Preview, using fallback: \(loadURL.lastPathComponent)")
                        if pendingQuickPreviewLoadsInExplore {
                            showPreviewImportGallery = true
                            pendingQuickPreviewLoadsInExplore = false
                        }
                    }
                }
            }
        } else if fileExtension == "ply" {
            clearSceneBatches()
            GeometryStreamingSystem.shared.enabled = false

            setEntityGaussian(entityId: entityId, filename: absolutePath, withExtension: fileExtension)
            print("✅ Quick Preview Gaussian loaded: \(loadURL.lastPathComponent)")
        }

        guard let camera = CameraSystem.shared.activeCamera,
              let cameraComponent = scene.get(component: CameraComponent.self, for: camera)
        else {
            handleError(.noActiveCamera)
            return
        }

        var forward = forwardDirectionVector(from: cameraComponent.rotation)
        forward *= -1.0
        let camPosition = cameraComponent.localPosition
        let spawnPosition = camPosition + forward * spawnDistance
        translateTo(entityId: entityId, position: spawnPosition)

        selectionManager.selectedEntity = entityId
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        if pendingQuickPreviewLoadsInExplore, fileExtension != "untold" {
            completeExploreQuickPreviewLoad(fileName: fileName, mode: .untoldAsset)
        }

        print("ℹ️ Quick Preview mode: File loaded with absolute path")
        print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
    }

    private func completeExploreQuickPreviewLoad(fileName: String, mode: QuickPreviewImportMode) {
        experienceMode = .explore
        showWelcomeStart = true
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = nil
        activeDemoCameraFrame = nil
        activePreviewSceneTitle = fileName
        activePreviewImportMode = mode
        pendingQuickPreviewLoadsInExplore = false
        clearExploreSelection()
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()
        enableExploreNavigationMode()
        revealCameraControlHintsIfNeeded()
    }

    private func deleteExistingQuickPreviewEntities() {
        let previewEntityIds = getAllGameEntities()
            .filter { hasComponent(entityId: $0, componentType: QuickPreviewComponent.self) }

        guard previewEntityIds.isEmpty == false else {
            return
        }

        for entityId in previewEntityIds {
            if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId),
               quickPreviewComp.runtimePreviewDirectoryPath.isEmpty == false
            {
                QuickPreviewRuntimeExportCache.removeCacheDirectory(at: URL(fileURLWithPath: quickPreviewComp.runtimePreviewDirectoryPath))
            }
            destroyEntity(entityId: entityId)
        }

        if let selectedId = selectionManager.selectedEntity,
           previewEntityIds.contains(selectedId)
        {
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
        }

        editor_entities = getAllGameEntities()
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()
    }

    // MARK: - Quick Preview Save Validation

    /// Checks if the scene contains any Quick Preview entities.
    /// Returns true if Quick Preview entities exist (and shows warning), false otherwise.
    private func checkForQuickPreviewEntities() -> Bool {
        var foundEntities: [(EntityID, String)] = []

        // Scan all entities for QuickPreviewComponent
        for entityId in getAllGameEntities() {
            if hasComponent(entityId: entityId, componentType: QuickPreviewComponent.self) {
                let entityName = getEntityName(entityId: entityId)
                let displayName = entityName.isEmpty ? "Entity \(entityId)" : entityName
                foundEntities.append((entityId, displayName))
            }
        }

        if !foundEntities.isEmpty {
            quickPreviewEntities = foundEntities
            showQuickPreviewWarning = true
            return true
        }

        return false
    }

    /// Deletes all Quick Preview entities and proceeds with save.
    private func deleteQuickPreviewEntitiesAndSave() {
        // Delete all Quick Preview entities
        for (entityId, entityName) in quickPreviewEntities {
            if let quickPreviewComp = scene.get(component: QuickPreviewComponent.self, for: entityId),
               quickPreviewComp.runtimePreviewDirectoryPath.isEmpty == false
            {
                QuickPreviewRuntimeExportCache.removeCacheDirectory(at: URL(fileURLWithPath: quickPreviewComp.runtimePreviewDirectoryPath))
            }
            destroyEntity(entityId: entityId)
            print("🗑️ Deleted Quick Preview entity: \(entityName)")
        }

        // Refresh UI
        editor_entities = getAllGameEntities()
        sceneGraphModel.refreshHierarchy()

        // Clear selection if it was a Quick Preview entity
        if let selectedId = selectionManager.selectedEntity,
           quickPreviewEntities.contains(where: { $0.0 == selectedId })
        {
            selectionManager.selectedEntity = nil
            activeEntity = .invalid
            removeGizmo()
        }

        quickPreviewEntities = []

        // Now proceed with the save
        if isSaveAs {
            // Re-trigger Save As flow
            editor_handleSaveAs()
        } else {
            // Re-trigger Save flow
            editor_handleSave()
        }
    }

    // MARK: - Project Switching Cleanup

    /// Cleans up the editor state when switching projects.
    /// Clears all entities, resets cameras/lights, and prepares for new project.
    private func cleanupForProjectSwitch() {
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
