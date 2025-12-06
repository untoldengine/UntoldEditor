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
    @State private var editor_entities: [EntityID] = getAllGameEntities()
    @StateObject private var selectionManager = SelectionManager()
    @StateObject private var sceneGraphModel = SceneGraphModel()
    @State private var assets: [String: [Asset]] = [:]
    @State private var selectedAsset: Asset? = nil
    @State private var isPlaying = false

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
                selectionManager: selectionManager, onSave: editor_handleSave,
                onLoad: editor_handleLoad, onClear: editor_clearScene,
                onPlayToggled: { isPlaying in editor_handlePlayToggle(isPlaying) },
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
            Divider()
            HStack {
                VStack {
                    SceneHierarchyView(selectionManager: selectionManager, sceneGraphModel: sceneGraphModel, entityList: editor_entities, onAddEntity_Editor: editor_addNewEntity, onRemoveEntity_Editor: editor_removeEntity)
                }

                VStack(spacing: 0) {
                    EditorSceneView(renderer: renderer!)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    TransformManipulationToolbar(controller: editorController!)
                        .frame(height: 40)
                    HStack(spacing: 0) {
                        AssetBrowserView(
                            assets: $assets,
                            selectedAsset: $selectedAsset,
                            selectionManager: selectionManager,
                            sceneGraphModel: sceneGraphModel,
                            editor_addEntityWithAsset: editor_addEntityWithAsset
                        )
                        .frame(width: 400)
                        // .tabItem { Label("Assets", systemImage: "shippingbox") }
                        Divider()
                        LogConsoleView()
                            .tabItem { Label("Console", systemImage: "terminal") }
                    }
                    .frame(height: 200)
                    // .clipped()
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

                    InspectorView(selectionManager: selectionManager, sceneGraphModel: sceneGraphModel, onAddName_Editor: editor_addName, selectedAsset: $selectedAsset)
                        .tabItem {
                            Label("Inspector", systemImage: "cube")
                        }
                }
                .frame(minWidth: 200, maxWidth: 250)
            }
        }
        .background(
            Color.editorBackground.ignoresSafeArea())
        .onAppear {
            sceneGraphModel.refreshHierarchy()
        }
    }

    private func editor_handleSave() {
        let sceneData: SceneData = serializeScene()
        saveScene(sceneData: sceneData)
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
        // CameraSystem.shared.activeCamera = gameMode ? findGameCamera() : findSceneCamera()
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
