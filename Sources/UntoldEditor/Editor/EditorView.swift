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

public struct EditorView: View {
    @State private var editor_entities: [EntityID] = getAllGameEntities()
    @StateObject private var selectionManager = SelectionManager()
    @StateObject private var sceneGraphModel = SceneGraphModel()
    @State private var assets: [String: [Asset]] = [:]
    @State private var selectedAsset: Asset? = nil
    @State private var isPlaying = false
    @State private var showSaveNamePrompt = false
    @State private var pendingSceneName: String = "untitled"
    @State private var showOverwriteAlert = false
    @State private var pendingTargetURL: URL?
    @State private var isSaveAs = false
    @State private var showSaveBasePathAlert = false
    @State private var useSceneCameraDuringPlay = false
    @State private var showQuickPreviewWarning = false
    @State private var quickPreviewEntities: [(EntityID, String)] = []

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
        ZStack {
            VStack {
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
                    onCreateCone: editor_createCone,
                    onQuickPreview: editor_handleQuickPreview
                )
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
                            onAddAreaLight: editor_createAreaLight,
                            onParentEntity: editor_parentEntity,
                            onUnparentEntity: editor_unparentEntity
                        )
                    }

                    VStack(spacing: 0) {
                        EditorSceneView(renderer: renderer!)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        TransformManipulationToolbar(controller: editorController!)
                            .frame(height: 40)
                        TabView {
                            AssetBrowserView(
                                assets: $assets,
                                selectedAsset: $selectedAsset,
                                selectionManager: selectionManager,
                                sceneGraphModel: sceneGraphModel,
                                editor_addEntityWithAsset: editor_addEntityWithAsset
                            )
                            .tabItem { Label("Assets", systemImage: "shippingbox") }

                            LogConsoleView()
                                .tabItem { Label("Console", systemImage: "terminal") }
                        }
                        .frame(height: 200)
                        .clipped()
                    }

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
            sceneGraphModel.refreshHierarchy()

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
        self.isPlaying = isPlaying
        gameMode = !gameMode
        updateActiveCameraForPlayMode()
        AnimationSystem.shared.isEnabled = isPlaying

        // Start/stop USC System
        if gameMode {
            USCSystem.shared.startPlayMode()
        } else {
            USCSystem.shared.stopPlayMode()
        }
    }

    private func updateActiveCameraForPlayMode() {
        if gameMode {
            CameraSystem.shared.activeCamera = useSceneCameraDuringPlay ? findSceneCamera() : findGameCamera()
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

    private func editor_handleQuickPreview() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Quick Preview - Select 3D File"
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "untold")!,
            UTType(filenameExtension: "ply")!,
            UTType(filenameExtension: "json")!,
        ]
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.message = "Select an Untold asset, PLY Gaussian, or tiled scene manifest to preview"

        guard openPanel.runModal() == .OK, let fileURL = openPanel.url else {
            return
        }

        let fileExtension = fileURL.pathExtension.lowercased()
        let absolutePath = fileURL.path

        if fileExtension == "json", !isTiledSceneManifest(fileURL) {
            Logger.log(message: "⚠️ Quick Preview JSON is not a tiled scene manifest: \(fileURL.lastPathComponent)")
            return
        }

        // Create a new entity for the preview
        removeGizmo()
        let entityId = createEntity()

        let fileName = fileURL.deletingPathExtension().lastPathComponent
        let uniqueName = "QuickPreview-\(fileName)-\(entityId)"
        setEntityName(entityId: entityId, name: uniqueName)

        // Mark this entity as a Quick Preview entity (cannot be saved)
        if let quickPreviewComp = scene.assign(to: entityId, component: QuickPreviewComponent.self) {
            quickPreviewComp.absoluteFilePath = absolutePath
            quickPreviewComp.fileExtension = fileExtension
            quickPreviewComp.originalFileName = fileName
        }

        if fileExtension == "untold" {
            // Load Untold runtime asset using absolute path
            setEntityMeshAsync(entityId: entityId, filename: absolutePath, withExtension: fileExtension) { success in
                if success {
                    print("✅ Quick Preview loaded: \(fileName).\(fileExtension)")
                } else {
                    print("⚠️ Failed to load Quick Preview, using fallback: \(fileName).\(fileExtension)")
                }
            }
        } else if fileExtension == "ply" {
            // Load Gaussian PLY using absolute path
            setEntityGaussian(entityId: entityId, filename: absolutePath, withExtension: fileExtension)
            print("✅ Quick Preview Gaussian loaded: \(fileName).\(fileExtension)")
        } else if fileExtension == "json" {
            setEntityStreamScene(entityId: entityId, url: fileURL) { success in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Quick Preview stream model loaded: \(fileName).\(fileExtension)")
                    } else {
                        print("⚠️ Failed to load Quick Preview stream model: \(fileName).\(fileExtension)")
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

        print("ℹ️ Quick Preview mode: File loaded with absolute path")
        print("⚠️ Note: Quick Preview entities cannot be saved to scenes (absolute paths not serialized)")
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
