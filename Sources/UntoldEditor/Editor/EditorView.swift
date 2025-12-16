import MetalKit
import SwiftUI
import UntoldEngine

public struct Asset: Identifiable {
    public let id = UUID()
    public let name: String
    public let category: String
    public let path: URL
    var isFolder: Bool = false
}

public struct EditorView: View {
    enum InspectorTab: String, CaseIterable, Hashable {
        case inspector = "Inspector"
        case environment = "Environment"
        case effects = "Effects"
    }

    @State private var editor_entities: [EntityID] = getAllGameEntities()
    @StateObject private var selectionManager = SelectionManager()
    @StateObject private var sceneGraphModel = SceneGraphModel()
    @State private var assets: [String: [Asset]] = [:]
    @State private var selectedAsset: Asset? = nil
    @State private var isPlaying = false
    @State private var inspectorTab: InspectorTab = .inspector
    @State private var showSaveNamePrompt = false
    @State private var pendingSceneName: String = "untitled"
    @State private var showOverwriteAlert = false
    @State private var pendingTargetURL: URL?
    @State private var isSaveAs = false
    @State private var showSaveBasePathAlert = false
    @State private var showAssetLibrary = false
    @State private var assetWindow: NSWindow?
    @State private var assetWindowDelegate: AssetWindowDelegate?

    var renderer: UntoldRenderer?

    public init() {
        let sharedSelectionManager = SelectionManager()
        _selectionManager = StateObject(wrappedValue: sharedSelectionManager)
        editorController = EditorController(selectionManager: sharedSelectionManager)
        renderer = UntoldRenderer.create(configuration: .editor)

        if let r = renderer, let v = renderer?.metalView {
            r.setupCallbacks(gameUpdate: { _ in }, handleInput: r.handleSceneInput)

            InputSystem.shared.setupGestureRecognizers(view: v)
            InputSystem.shared.setupEventMonitors()
        }

        gameMode = isPlaying
        AnimationSystem.shared.isEnabled = isPlaying
    }

    public var body: some View {
        VStack {
            ToolbarView(
                selectionManager: selectionManager,
                onSave: editor_handleSave,
                onSaveAs: editor_handleSaveAs,
                onClear: editor_clearScene,
                onPlayToggled: { isPlaying in
                    editor_handlePlayToggle(isPlaying)
                },
                onShowAssets: {
                    openAssetWindow()
                },
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
            .popover(isPresented: $showAssetLibrary, arrowEdge: .bottom) {
                VStack(spacing: 0) {
                    HStack {
                        Text("Assets Library")
                            .font(.headline)
                        Spacer()
                        Button("Close") { showAssetLibrary = false }
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding()
                    .background(Color.editorPanelBackground.opacity(0.9))

                    Divider()

                    AssetBrowserView(
                        assets: $assets,
                        selectedAsset: $selectedAsset,
                        selectionManager: selectionManager,
                        sceneGraphModel: sceneGraphModel,
                        editor_addEntityWithAsset: editor_addEntityWithAsset
                    )
                    .frame(minWidth: 700, minHeight: 500)
                }
                .frame(minWidth: 720, minHeight: 540)
            }
            Divider()
            HStack {
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
                        onAddAreaLight: editor_createAreaLight
                    )
                }

                VStack(spacing: 0) {
                    EditorSceneView(renderer: renderer!)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    TransformManipulationToolbar(controller: editorController!)
                        .frame(height: 40)
                    LogConsoleView()
                        .frame(height: 260)
                }

                VStack(spacing: 8) {
                    Picker("", selection: $inspectorTab) {
                        ForEach(InspectorTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 4)

                    Divider()

                    Group {
                        switch inspectorTab {
                        case .inspector:
                            InspectorView(
                                selectionManager: selectionManager,
                                sceneGraphModel: sceneGraphModel,
                                onAddName_Editor: editor_addName,
                                selectedAsset: $selectedAsset
                            )
                        case .environment:
                            ScrollView { EnvironmentView(selectedAsset: $selectedAsset) }
                        case .effects:
                            ScrollView { PostProcessingEditorView() }
                        }
                    }
                }
                .onChange(of: selectionManager.selectedEntity) { _, newValue in
                    if let entity = newValue, entity != .invalid {
                        inspectorTab = .inspector
                    }
                }
                .frame(minWidth: 240, maxWidth: 320)
            }
        }
        .background(
            LinearGradient(
                colors: [Color.editorBackground, Color.editorPanelBackground.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea())
        .onAppear {
            sceneGraphModel.refreshHierarchy()
        }
        .sheet(isPresented: $showSaveNamePrompt) {
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
        .alert("Set Asset Folder First", isPresented: $showSaveBasePathAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Please set the Asset Folder in the Asset Browser before saving scenes.")
        }
    }

    private func editor_handleSave() {
        guard assetBasePath != nil else {
            showSaveBasePathAlert = true
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

        let targetURL = scenesFolder.appendingPathComponent(name).appendingPathExtension("json")
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

        if FileManager.default.fileExists(atPath: destinationURL.path) && !overwrite {
            showOverwriteAlert = true
            return
        }

        saveSceneDirect(sceneData: sceneData, to: destinationURL)
        editorController?.currentSceneURL = destinationURL
        showSaveNamePrompt = false
        showOverwriteAlert = false
        isSaveAs = false
    }

    // MARK: - Asset Library Window

    private func openAssetWindow() {
        if let existing = assetWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = AssetBrowserView(
            assets: $assets,
            selectedAsset: $selectedAsset,
            selectionManager: selectionManager,
            sceneGraphModel: sceneGraphModel,
            editor_addEntityWithAsset: editor_addEntityWithAsset
        )

        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Assets Library"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 760, height: 520))
        window.minSize = NSSize(width: 620, height: 420)
        window.level = .floating // keep above editor while arranging assets
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.9
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let delegate = AssetWindowDelegate { 
            // Window is closing — clear our references
            self.assetWindow = nil
            self.assetWindowDelegate = nil
        }
        window.delegate = delegate
        assetWindowDelegate = delegate

        assetWindow = window
    }

    private func editor_handleLoad() {
        var sceneData: SceneData?

        // Check if a scene is selected in the Asset Browser
        if let asset = selectedAsset,
           asset.category == "Scenes",
           asset.path.pathExtension.lowercased() == "json"
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

        let gameCameraEntityID = findGameCamera()

        if gameCameraEntityID == .invalid {
            return
        }

        let eye = getCameraEye(entityId: sceneCameraEntityID)
        let up = getCameraUp(entityId: sceneCameraEntityID)
        let target = getCameraTarget(entityId: sceneCameraEntityID)

        cameraLookAt(entityId: gameCameraEntityID, eye: eye, target: target, up: up)
    }

    private func editor_loadUSDScene() {
        guard let url = openFilePicker() else { return }

        let filename = url.deletingPathExtension().lastPathComponent
        let withExtension = url.pathExtension

        loadScene(filename: filename, withExtension: withExtension)
        editor_entities = getAllGameEntities()
        selectionManager.selectedEntity = nil
        activeEntity = .invalid
        selectionManager.objectWillChange.send()

        CameraSystem.shared.activeCamera = findSceneCamera()
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
        self.isPlaying = isPlaying
        gameMode = !gameMode
        // For now, during "play" mode, the camera will keep being the scene camera
        CameraSystem.shared.activeCamera = gameMode ? findGameCamera() : findSceneCamera()
        AnimationSystem.shared.isEnabled = isPlaying

        // Start/stop USC System
        if gameMode {
            USCSystem.shared.startPlayMode()
        } else {
            USCSystem.shared.stopPlayMode()
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
        setEntityMesh(entityId: selectionManager.selectedEntity!, filename: filename!, withExtension: withExtension!)

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
}
