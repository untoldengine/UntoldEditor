//
//  InspectorView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import simd
import SwiftUI
import UntoldEngine

public struct ComponentOption_Editor: Identifiable {
    public let id: Int
    public let name: String
    public let type: Any.Type
    public let view: (EntityID?, Asset?, @escaping () -> Void) -> AnyView
    public let onAdd: ((EntityID) -> Void)?

    public init(id: Int, name: String, type: Any.Type, view: @escaping (EntityID?, Asset?, @escaping () -> Void) -> AnyView, onAdd: ((EntityID) -> Void)? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.view = view
        self.onAdd = onAdd
    }
}

func openFilePicker() -> URL? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    return panel.runModal() == .OK ? panel.urls.first : nil
}

private func onAddMesh_Editor(entityId: EntityID, url: URL) {
    let filename = url.deletingPathExtension().lastPathComponent
    let withExtension = url.pathExtension

    setEntityMeshAsync(entityId: entityId, filename: filename, withExtension: withExtension) { success in
        if success {
            print("✅ Mesh loaded: \(filename).\(withExtension)")
        } else {
            print("⚠️ Failed to load mesh, using fallback: \(filename).\(withExtension)")
        }
    }
}

private func onAddAnimation_Editor(entityId: EntityID, url: URL) {
    guard canAuthorAnimationComponent(entityId: entityId) else {
        print("⚠️ Select a mesh node to assign animation")
        return
    }

    let filename = url.deletingPathExtension().lastPathComponent
    let withExtension = url.pathExtension

    if !hasComponent(entityId: entityId, componentType: AnimationComponent.self) {
        registerComponent(entityId: entityId, componentType: AnimationComponent.self)
    }

    setEntityAnimations(entityId: entityId, filename: filename, withExtension: withExtension, name: filename)
    // changeAnimation(entityId: entityId, name: filename)

    guard let animationComponent = scene.get(component: AnimationComponent.self, for: entityId) else {
        handleError(.noAnimationComponent, entityId)
        return
    }

    if animationComponent.animationsFilenames.contains(url) == false {
        animationComponent.animationsFilenames.append(url)
    }
}

public func addComponent_Editor(componentOption: ComponentOption_Editor) {
    availableComponents_Editor.append(componentOption)
}

var availableComponents_Editor: [ComponentOption_Editor] = [
    ComponentOption_Editor(id: getComponentId(for: RenderComponent.self), name: "Render Component", type: RenderComponent.self, view: { selectedId, asset, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    RenderingEditorView(entityId: entityId, asset: asset, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: LocalTransformComponent.self), name: "Transform Component", type: LocalTransformComponent.self, view: { selectedEntityId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedEntityId {
                    TransformationEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: AnimationComponent.self), name: "Animation Component", type: AnimationComponent.self, view: { selectedId, asset, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    AnimationEditorView(entityId: entityId, asset: asset, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: KineticComponent.self), name: "Kinetic Component", type: KineticComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    KineticEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: DirectionalLightComponent.self), name: "Dir Light Component", type: DirectionalLightComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    DirLightEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: PointLightComponent.self), name: "Point Light Component", type: PointLightComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    PointLightEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: SpotLightComponent.self), name: "Spot Light Component", type: SpotLightComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    SpotLightEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: AreaLightComponent.self), name: "Area Light Component", type: AreaLightComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    AreaLightEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),
    ComponentOption_Editor(id: getComponentId(for: CameraComponent.self), name: "Camera Component", type: CameraComponent.self, view: { selectedId, _, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    CameraEditorView(entityId: entityId, refreshView: refreshView)
                }
            }
        )
    }),

    ComponentOption_Editor(id: getComponentId(for: GaussianComponent.self), name: "Gaussian Component", type: GaussianComponent.self, view: { selectedId, asset, refreshView in
        AnyView(
            Group {
                if let entityId = selectedId {
                    GaussianEditorView(entityId: entityId, asset: asset, refreshView: refreshView)
                }
            }
        )
    }),

    ComponentOption_Editor(
        id: getComponentId(for: LODComponent.self),
        name: "LOD Component",
        type: LODComponent.self,
        view: { selectedId, asset, refreshView in
            AnyView(
                Group {
                    if let entityId = selectedId {
                        LODComponentEditorView(entityId: entityId, asset: asset, refreshView: refreshView)
                    }
                }
            )
        },
        onAdd: { entityId in
            setEntityLodComponent(entityId: entityId)
        }
    ),
]

/// Script Component - controlled by feature flag
var scriptComponent_Editor: ComponentOption_Editor = .init(id: getComponentId(for: ScriptComponent.self), name: "Script Component", type: ScriptComponent.self, view: { selectedId, asset, refreshView in
    AnyView(
        Group {
            if let entityId = selectedId {
                ScriptComponentInspector(entityId: entityId, asset: asset, refreshView: refreshView)
            }
        }
    )
})

func mergeEntityComponents(
    selectedEntity: EntityID?,
    editor_availableComponents: [ComponentOption_Editor]
) -> [ObjectIdentifier: ComponentOption_Editor] {
    guard let entityId = selectedEntity else { return [:] }

    var mergedComponents = EditorComponentsState.shared.components[entityId] ?? [:]

    let existingComponentIDs: [Int] = getAllEntityComponentsIds(entityId: entityId)

    // Include script component if feature flag is enabled
    var allComponents = editor_availableComponents
    if EditorFeatureFlags.enableScriptComponent, EditorAuthoringMode.sceneCompositionOnly == false {
        allComponents.append(scriptComponent_Editor)
    }

    let matchingComponents = allComponents.filter { existingComponentIDs.contains($0.id) }

    for match in matchingComponents {
        guard canShowComponentInInspector(componentType: match.type, for: entityId) else {
            continue
        }

        let key = ObjectIdentifier(match.type)

        if mergedComponents[key] == nil {
            mergedComponents[key] = match
        }
    }

    return mergedComponents.filter { canShowComponentInInspector(componentType: $0.value.type, for: entityId) }
}

func sortEntityComponents(componentOption_Editor: [ObjectIdentifier: ComponentOption_Editor]) -> [ComponentOption_Editor] {
    Array(componentOption_Editor.values).sorted { lhs, rhs in
        let order: [String: Int] = [
            "Render Component": 1,
            "Transform Component": 2,
            "Animation Component": 3,
            "Kinetic Component": 4,
        ]
        return (order[lhs.name] ?? Int.max) < (order[rhs.name] ?? Int.max)
    }
}

struct InspectorView: View {
    @ObservedObject var selectionManager: SelectionManager
    @ObservedObject var sceneGraphModel: SceneGraphModel
    @ObservedObject var editorComponentsState = EditorComponentsState.shared
    var onAddName_Editor: () -> Void
    // @State private var editor_entityComponents: [EntityID: [ObjectIdentifier: ComponentOption_Editor]] = [:]
    @FocusState private var isNameTextFieldFocused: Bool
    @State private var nameEditStartValue: String?
    @Binding var selectedAsset: Asset?

    var body: some View {
        VStack(alignment: .leading) {
            Text("Inspector")
                .font(.headline)
                .padding(.bottom, 8)

            if let entityId = selectionManager.selectedEntity, entityId != .invalid {
                ScrollView { // Make the entire inspector scrollable
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Name")
                            TextField("Set Entity Name", text: Binding(
                                get: { getEntityName(entityId: entityId) },
                                set: {
                                    setEntityName(entityId: entityId, name: $0)
                                }
                            ))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .padding()
                            .focused($isNameTextFieldFocused)
                            .onSubmit {
                                if let oldName = nameEditStartValue {
                                    EditorUndoManager.shared.registerNameChange(
                                        entityId: entityId,
                                        oldName: oldName,
                                        newName: getEntityName(entityId: entityId)
                                    )
                                }
                                nameEditStartValue = nil
                                onAddName_Editor()
                                refreshView()
                                isNameTextFieldFocused = false
                            }
                            .onChange(of: isNameTextFieldFocused) { _, isFocused in
                                if isFocused {
                                    nameEditStartValue = getEntityName(entityId: entityId)
                                } else if let oldName = nameEditStartValue {
                                    EditorUndoManager.shared.registerNameChange(
                                        entityId: entityId,
                                        oldName: oldName,
                                        newName: getEntityName(entityId: entityId)
                                    )
                                    nameEditStartValue = nil
                                    refreshView()
                                }
                            }
                        }

                        if isDerivedAssetNode(entityId) {
                            AssetNodeInspectorBanner(entityId: entityId, selectionManager: selectionManager)
                        }

                        if let inspectedMesh = selectionManager.inspectedMesh,
                           inspectedMesh.entityId == entityId
                        {
                            RenderingEditorView(
                                entityId: entityId,
                                asset: selectedAsset,
                                refreshView: refreshView,
                                meshIndex: inspectedMesh.meshIndex,
                                inspectionOnly: true
                            )
                            Divider()
                        }

                        if let entityId = selectionManager.selectedEntity {
                            let mergedComponents = mergeEntityComponents(
                                selectedEntity: entityId,
                                editor_availableComponents: availableComponents_Editor
                            )

                            let sortedComponents = sortEntityComponents(componentOption_Editor: mergedComponents)

                            // Static Batching Section - Show for any entity with renderable hierarchy
                            if EditorAuthoringMode.sceneCompositionOnly == false, isDerivedAssetNode(entityId) == false {
                                StaticBatchingEditorView(entityId: entityId, refreshView: refreshView)
                            }

                            ForEach(sortedComponents, id: \.id) { editor_component in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(editor_component.name)
                                            .font(.headline)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if canRemoveComponentFromInspector(componentType: editor_component.type, from: entityId) {
                                            Button(action: {
                                                removeComponentFromEntity_Editor(componentType: editor_component.type)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                            .buttonStyle(BorderlessButtonStyle())
                                        }
                                    }

                                    editor_component.view(entityId, selectedAsset, refreshView)
                                        .frame(minWidth: 200, maxWidth: 250)
                                }
                                Divider()
                            }

                            let addableComponents = availableComponentsWithFlags()
                            if addableComponents.isEmpty == false {
                                Menu {
                                    ForEach(addableComponents, id: \.id) { component in
                                        Button(component.name) {
                                            addComponentToEntity_Editor(componentType: component.type)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Component")
                                            .fontWeight(.regular)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                                .menuStyle(.borderlessButton)
                                .padding(.top, 8)
                            }

                        } else {
                            Text("No entity selected").foregroundColor(.gray)
                        }
                    }
                }
                .frame(maxHeight: .infinity) // Ensure ScrollView takes available space

            } else {
                Text("No entity selected")
                    .foregroundColor(.gray)
            }
        }
        .frame(minWidth: 200, maxWidth: 250)
        .padding()
    }

    func addComponentToEntity_Editor(componentType: Any.Type) {
        guard let entityId = selectionManager.selectedEntity else { return }
        guard canAddComponentFromInspector(componentType: componentType, to: entityId) else { return }

        let key = ObjectIdentifier(componentType)

        var allComponents = availableComponents_Editor
        if EditorFeatureFlags.enableScriptComponent, EditorAuthoringMode.sceneCompositionOnly == false {
            allComponents.append(scriptComponent_Editor)
        }
        if let component = allComponents.first(where: { ObjectIdentifier($0.type) == key }) {
            // Ensure the entity has an entry in the dictionary
            if editorComponentsState.components[entityId] == nil {
                editorComponentsState.components[entityId] = [:]
            }

            // Add component to the entity-specific dictionary
            editorComponentsState.components[entityId]?[key] = component

            component.onAdd?(entityId)

            if key == ObjectIdentifier(DirectionalLightComponent.self) {
                createDirLight(entityId: entityId)
            } else if key == ObjectIdentifier(PointLightComponent.self) {
                createPointLight(entityId: entityId)
            } else if key == ObjectIdentifier(SpotLightComponent.self) {
                createSpotLight(entityId: entityId)
            } else if key == ObjectIdentifier(AreaLightComponent.self) {
                createAreaLight(entityId: entityId)
            } else if key == ObjectIdentifier(KineticComponent.self) {
                setEntityKinetics(entityId: entityId)
            } else if key == ObjectIdentifier(CameraComponent.self) {
                createGameCamera(entityId: entityId)
            }
        }
    }

    func removeComponentFromEntity_Editor(componentType: Any.Type) {
        guard let entityId = selectionManager.selectedEntity else { return }
        guard canRemoveComponentFromInspector(componentType: componentType, from: entityId) else { return }

        let key = ObjectIdentifier(componentType)

        // Remove component from the editor's state
        editorComponentsState.components[entityId]?[key] = nil

        // Remove component from the engine's scene
        if key == ObjectIdentifier(RenderComponent.self) {
            scene.remove(component: RenderComponent.self, from: entityId)
        } else if key == ObjectIdentifier(LocalTransformComponent.self) {
            scene.remove(component: LocalTransformComponent.self, from: entityId)
        } else if key == ObjectIdentifier(AnimationComponent.self) {
            scene.remove(component: AnimationComponent.self, from: entityId)
        } else if key == ObjectIdentifier(KineticComponent.self) {
            scene.remove(component: KineticComponent.self, from: entityId)
        } else if key == ObjectIdentifier(DirectionalLightComponent.self) {
            scene.remove(component: DirectionalLightComponent.self, from: entityId)
        } else if key == ObjectIdentifier(PointLightComponent.self) {
            scene.remove(component: PointLightComponent.self, from: entityId)
        } else if key == ObjectIdentifier(SpotLightComponent.self) {
            scene.remove(component: SpotLightComponent.self, from: entityId)
        } else if key == ObjectIdentifier(AreaLightComponent.self) {
            scene.remove(component: AreaLightComponent.self, from: entityId)
        } else if key == ObjectIdentifier(CameraComponent.self) {
            scene.remove(component: CameraComponent.self, from: entityId)
        } else if key == ObjectIdentifier(GaussianComponent.self) {
            scene.remove(component: GaussianComponent.self, from: entityId)
        } else if key == ObjectIdentifier(ScriptComponent.self) {
            scene.remove(component: ScriptComponent.self, from: entityId)
        } else if key == ObjectIdentifier(LODComponent.self) {
            scene.remove(component: LODComponent.self, from: entityId)
        }

        refreshView()
    }

    private func refreshView() {
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()
    }

    private func availableComponentsWithFlags() -> [ComponentOption_Editor] {
        var components = availableComponents_Editor
        if EditorFeatureFlags.enableScriptComponent, EditorAuthoringMode.sceneCompositionOnly == false {
            components.append(scriptComponent_Editor)
        }
        if let entityId = selectionManager.selectedEntity {
            components = components.filter { canAddComponentFromInspector(componentType: $0.type, to: entityId) }
        }
        return components
    }
}

/*
 struct TemplateEditorView: View{
 let entityId: EntityID
 let asset: Asset?
 let refreshView: () -> Void

 var body: some View{

 }
 }
 */

// MARK: - Static Batching Section

struct StaticBatchingEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @State private var staticBatchCheckboxState: Bool = false

    /// Check if entity or any of its children have RenderComponent
    private func hasRenderableHierarchy(entityId: EntityID) -> Bool {
        // Check self
        if hasComponent(entityId: entityId, componentType: RenderComponent.self) {
            return true
        }

        // Check children recursively
        let children = getEntityChildren(parentId: entityId)
        for child in children {
            if hasRenderableHierarchy(entityId: child) {
                return true
            }
        }

        return false
    }

    /// Check if entity or any of its children have StaticBatchComponent
    private func isMarkedAsStatic(entityId: EntityID) -> Bool {
        // Check self
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            return true
        }

        // Check children recursively
        let children = getEntityChildren(parentId: entityId)
        for child in children {
            if isMarkedAsStatic(entityId: child) {
                return true
            }
        }

        return false
    }

    var body: some View {
        // Only show if entity or children have RenderComponent (but not lights)
        if hasRenderableHierarchy(entityId: entityId), hasComponent(entityId: entityId, componentType: LightComponent.self) == false {
            VStack(alignment: .leading, spacing: 4) {
                Text("Static Batching")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let hasOwnRenderComponent = hasComponent(entityId: entityId, componentType: RenderComponent.self)
                let labelText = hasOwnRenderComponent ? "Mark as Static" : "Mark Children as Static"
                let helpText = hasOwnRenderComponent
                    ? "Enable static batching for this entity (combines geometry to reduce draw calls)"
                    : "Enable static batching for all children of this entity (combines geometry to reduce draw calls)"

                Toggle(isOn: Binding(
                    get: { staticBatchCheckboxState },
                    set: { isStatic in
                        if isStatic {
                            setEntityStaticBatchComponent(entityId: entityId)
                        } else {
                            removeEntityStaticBatchComponent(entityId: entityId)
                        }
                        staticBatchCheckboxState = isStatic
                        refreshView()
                    }
                )) {
                    HStack {
                        Image(systemName: "square.3.layers.3d")
                            .foregroundColor(.blue)
                        Text(labelText)
                            .font(.callout)
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(8)
                .help(helpText)
                .onAppear {
                    // Update checkbox state when view appears
                    staticBatchCheckboxState = isMarkedAsStatic(entityId: entityId)
                }
                .onChange(of: entityId) { newEntityId in
                    // Update checkbox state when entity selection changes
                    staticBatchCheckboxState = isMarkedAsStatic(entityId: newEntityId)
                }
            }

            Divider()
        }
    }
}

struct RenderingEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void
    var meshIndex: Int = 0
    var inspectionOnly: Bool = false
    @State private var hasPendingUntoldWrite = false
    @State private var untoldUpdateStatus: String?

    var body: some View {
        let readOnlyRender = EditorAuthoringMode.sceneCompositionOnly || inspectionOnly

        return VStack(alignment: .leading) {
            Text("Mesh")

            HStack(spacing: 12) {
                Text(meshLabel)

                if readOnlyRender == false {
                    Button(action: {
                        let selectedCategory: AssetCategory = .models
                        if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                            onAddMesh_Editor(entityId: entityId, url: assetPath)
                        }
                        refreshView()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.white)
                            Text("Assign")
                                .fontWeight(.regular)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(Color.editorAccent)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(8)

            if hasComponent(entityId: entityId, componentType: RenderComponent.self),
               hasComponent(entityId: entityId, componentType: LightComponent.self) == false
            {
                Text("Material Properties")
                    .font(.headline)
                    .padding(.bottom, 4)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 24) {
                        ForEach(TextureType.allCases) { type in
                            let image: NSImage? = {
                                if let img = getMaterialTextureImage(entityId: entityId, type: type, meshIndex: meshIndex) {
                                    return img
                                } else {
                                    return NSImage(named: "Default Texture")
                                }
                            }()

                            VStack(alignment: .center, spacing: 8) {
                                Button(action: {
                                    if asset?.category == "Materials", let path = asset?.path {
                                        updateMaterialTexture(entityId: entityId, textureType: type, path: path, meshIndex: meshIndex)
                                        refreshView()
                                    }
                                }) {
                                    if let image {
                                        Image(nsImage: image)
                                            .resizable()
                                            .frame(width: 64, height: 64)
                                            .cornerRadius(6)
                                    } else {
                                        Image(systemName: "photo")
                                            .resizable()
                                            .frame(width: 64, height: 64)
                                            .foregroundColor(.gray)
                                    }
                                }
                                .buttonStyle(PlainButtonStyle())

                                HStack(spacing: 8) {
                                    Button(action: {
                                        removeMaterialTexture(entityId: entityId, textureType: type, meshIndex: meshIndex)
                                        refreshView()
                                    }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())

                                    if canRestoreEmbeddedTexture(entityId: entityId, type: type, meshIndex: meshIndex) {
                                        Button(action: {
                                            restoreEmbeddedTexture(entityId: entityId, textureType: type, meshIndex: meshIndex)
                                            refreshView()
                                        }) {
                                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .help("Restore original embedded texture")
                                    }
                                }
                                .disabled(inspectionOnly)
                                .opacity(inspectionOnly ? 0.7 : 1.0)

                                Text(type.displayName)
                                    .font(.caption)
                                    .padding(.top, 4)

                                Divider().padding(.vertical, 4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Wrap Mode")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Picker("", selection: bindingForWrapMode(entityId: entityId, textureType: type, meshIndex: meshIndex, onChange: refreshView)) {
                                        ForEach(WrapMode.allCases) { mode in
                                            Text(mode.description).tag(mode)
                                        }
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: 100)
                                }
                                .disabled(inspectionOnly)
                                .opacity(inspectionOnly ? 0.7 : 1.0)
                            }
                            .frame(width: 100)
                        }
                    }
                    .padding(.horizontal, 12)
                }

                HStack {
                    Text("UV Scale")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    TextInputNumberView(
                        label: "",
                        value: Binding(
                            get: { getMaterialSTScale(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialSTScale(entityId: entityId, stScale: newValue, meshIndex: meshIndex)
                                refreshView()
                            }
                        )
                    )
                    .frame(width: 60)
                    .disabled(inspectionOnly)
                    .opacity(inspectionOnly ? 0.7 : 1.0)
                }

                Divider()
                HStack {
                    // Base Color Picker
                    VStack {
                        ColorPicker("", selection: Binding(
                            get: { colorFromSimd(getMaterialBaseColor(entityId: entityId, meshIndex: meshIndex)) },
                            set: { newColor in updateMaterialColor(entityId: entityId, color: newColor, meshIndex: meshIndex) }
                        ))
                        .frame(width: 60)
                        .disabled(inspectionOnly)
                        .opacity(inspectionOnly ? 0.7 : 1.0)

                        Text("Base Color")
                            .font(.caption)
                    }

                    // Roughness Input
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialRoughness(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialRoughness(entityId: entityId, roughness: newValue, meshIndex: meshIndex)
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Roughness")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Metallic Input
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialMetallic(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialMetallic(entityId: entityId, metallic: newValue, meshIndex: meshIndex)
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Metallic")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    VStack {
                        TextInputNumberView(
                            label: "",
                            value: Binding(
                                get: { getMaterialOpacity(entityId: entityId, meshIndex: meshIndex) },
                                set: { newValue in
                                    updateMaterialOpacity(entityId: entityId, opacity: newValue, meshIndex: meshIndex, submeshIndex: 0)
                                    if inspectionOnly, isUntoldBackedMesh {
                                        hasPendingUntoldWrite = true
                                        untoldUpdateStatus = nil
                                    }
                                    refreshView()
                                }
                            )
                        )
                        .frame(width: 60)

                        Text("Opacity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack {
                        Picker("", selection: Binding(
                            get: { getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialAlphaMode(entityId: entityId, mode: newValue, meshIndex: meshIndex)
                                if inspectionOnly, isUntoldBackedMesh {
                                    hasPendingUntoldWrite = true
                                    untoldUpdateStatus = nil
                                }
                                refreshView()
                            }
                        )) {
                            ForEach(MaterialAlphaMode.allCases) { mode in
                                Text(mode.description).tag(mode)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 120)

                        Text("Alpha Mask")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if inspectionOnly, isUntoldBackedMesh, hasPendingUntoldWrite {
                    Button(action: updateUntoldAsset) {
                        Text("Update .untold")
                    }
                    .buttonStyle(.borderedProminent)

                    if let untoldUpdateStatus {
                        Text(untoldUpdateStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                VStack {
                    TextInputVectorView(
                        label: "",
                        value: Binding(
                            get: { getMaterialEmmissive(entityId: entityId, meshIndex: meshIndex) },
                            set: { newValue in
                                updateMaterialEmmisive(entityId: entityId, emmissive: newValue, meshIndex: meshIndex)
                                refreshView()
                            }
                        )
                    )
                    .frame(width: 200)
                    .disabled(inspectionOnly)
                    .opacity(inspectionOnly ? 0.7 : 1.0)

                    Text("Emmisive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
        .onChange(of: entityId) { _ in
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
        .onChange(of: meshIndex) { _ in
            hasPendingUntoldWrite = false
            untoldUpdateStatus = nil
        }
    }

    private var meshLabel: String {
        guard let renderComponent = scene.get(component: RenderComponent.self, for: entityId),
              renderComponent.mesh.indices.contains(meshIndex)
        else {
            return getAssetURLString(entityId: entityId) ?? " "
        }

        let mesh = renderComponent.mesh[meshIndex]
        let name = mesh.modelMDLMesh.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if inspectionOnly, !name.isEmpty {
            return name
        }

        return getAssetURLString(entityId: entityId) ?? (name.isEmpty ? " " : name)
    }

    private var isUntoldBackedMesh: Bool {
        resolveUntoldAssetURL(entityId: entityId) != nil
    }

    private func updateUntoldAsset() {
        do {
            try persistAlphaMaterialOverridesToUntold(
                entityId: entityId,
                meshIndex: meshIndex,
                opacity: getMaterialOpacity(entityId: entityId, meshIndex: meshIndex),
                alphaCutoff: getMaterialAlphaCutoff(entityId: entityId, meshIndex: meshIndex),
                roughness: getMaterialRoughness(entityId: entityId, meshIndex: meshIndex),
                metallic: getMaterialMetallic(entityId: entityId, meshIndex: meshIndex),
                alphaMode: getMaterialAlphaMode(entityId: entityId, meshIndex: meshIndex)
            )
            hasPendingUntoldWrite = false
            untoldUpdateStatus = "Updated \(resolveUntoldAssetURL(entityId: entityId)?.lastPathComponent ?? ".untold")"
            refreshView()
        } catch {
            untoldUpdateStatus = error.localizedDescription
        }
    }
}

private struct AssetNodeInspectorBanner: View {
    let entityId: EntityID
    @ObservedObject var selectionManager: SelectionManager

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isBindableAssetMeshNode(entityId) ? "cube.fill" : "square.stack.3d.up")
                .foregroundColor(.secondary)

            Text(isBindableAssetMeshNode(entityId) ? "Mesh Node" : "Asset Node")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            if let rootId = assetRootEntityId(for: entityId), rootId != .invalid {
                Button(action: {
                    selectionManager.selectEntity(entityId: rootId)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.left")
                        Text(getEntityName(entityId: rootId))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Select asset root")
            }
        }
        .padding(6)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(6)
    }
}

private struct ReadOnlyVectorView: View {
    let label: String
    let value: simd_float3

    var body: some View {
        VStack(alignment: .leading) {
            Text(label)
                .font(.headline)

            HStack {
                vectorValue(value.x)
                vectorValue(value.y)
                vectorValue(value.z)
            }
        }
        .padding(.vertical, 4)
    }

    private func vectorValue(_ value: Float) -> some View {
        Text(value, format: .number.precision(.fractionLength(3)))
            .frame(width: 60)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .cornerRadius(4)
    }
}

struct TransformationEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    @State private var showStaticBatchWarning = false

    var body: some View {
        Text("Transform Properties")

        // Warning banner if entity is marked as static
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("This entity is marked for static batching. Transforming it will disable batching.")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            .padding(6)
            .background(Color.orange.opacity(0.1))
            .cornerRadius(6)
        }

        if let localTransformComponent = scene.get(component: LocalTransformComponent.self, for: entityId) {
            let position = getLocalPosition(entityId: entityId)
            let orientation = simd_float3(localTransformComponent.rotationX, localTransformComponent.rotationY, localTransformComponent.rotationZ)
            let scale = getScale(entityId: entityId)

            TextInputVectorView(label: "Position", value: Binding(
                get: { position },
                set: { newPosition in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    translateTo(entityId: entityId, position: newPosition)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Orientation", value: Binding(
                get: { orientation },
                set: { newOrientation in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    applyAxisRotations(entityId: entityId, axis: newOrientation)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Scale", value: Binding(
                get: { scale },
                set: { newScale in
                    let before = EditorTransformSnapshot(entityId: entityId)
                    handleTransformChange()
                    scaleTo(entityId: entityId, scale: newScale)
                    EditorUndoManager.shared.registerTransformChange(
                        entityId: entityId,
                        before: before,
                        after: EditorTransformSnapshot(entityId: entityId)
                    )
                    refreshView()
                }
            ))
        } else {
            Text("No transform data")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func handleTransformChange() {
        if hasComponent(entityId: entityId, componentType: StaticBatchComponent.self) {
            removeEntityStaticBatchComponent(entityId: entityId)
            // Optionally regenerate batches without this entity
            if isBatchingEnabled() {
                generateBatches()
            }
        }
    }
}

struct AnimationEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    var body: some View {
        Text("Animation Properties")
        // List of currently linked animations
        let animationClips: [String] = getAllAnimationClips(entityId: entityId)

        List {
            ForEach(animationClips, id: \.self) { animation in
                HStack {
                    Text(animation) // Display animation name
                    Spacer()
                    Button(action: {
                        removeAnimationClip(entityId: entityId, animationClip: animation)
                        refreshView()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .frame(height: 100)
        .scrollContentBackground(.hidden) // Hide default background
        .background(Color.gray.opacity(0.3)) // Apply a dark background
        .cornerRadius(8) // Optional: Add corner radius for a sleek look
        // Add animation UI
        HStack {
            Button(action: {
                let selectedCategory: AssetCategory = .animations
                if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                    onAddAnimation_Editor(entityId: entityId, url: assetPath)
                }
                refreshView()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.white)
                    Text("Assign")
                        .fontWeight(.regular)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.editorAccent)
                .foregroundColor(.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}

struct KineticEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Kinetic System")

        if hasComponent(entityId: entityId, componentType: KineticComponent.self) {
            let mass = getMass(entityId: entityId)
            TextInputNumberView(label: "Mass", value: Binding(
                get: { mass },
                set: { newMass in
                    setMass(entityId: entityId, mass: newMass)
                    refreshView()
                }
            ))
        }
    }
}

struct DirLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)

                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                TextInputNumberView(label: "Intensity", value: Binding(
                    get: { intensity },
                    set: { newIntensity in
                        updateLightIntensity(entityId: entityId, intensity: newIntensity)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct PointLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: PointLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)
                let falloff: Float = getLightFalloff(entityId: entityId)
                let radius: Float = getLightRadius(entityId: entityId)

                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    TextInputNumberView(label: "Brighness", value: Binding(
                        get: { intensity },
                        set: { newIntensity in
                            updateLightIntensity(entityId: entityId, intensity: newIntensity)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Falloff", value: Binding(
                        get: { falloff },
                        set: { newFalloff in
                            updateLightFalloff(entityId: entityId, falloff: newFalloff)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Radius", value: Binding(
                        get: { radius },
                        set: { newRadius in
                            updateLightRadius(entityId: entityId, radius: newRadius)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct SpotLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: SpotLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let falloff: Float = getLightFalloff(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)
                let coneAngle: Float = getLightConeAngle(entityId: entityId)
                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    TextInputNumberView(label: "Brightness", value: Binding(
                        get: { intensity },
                        set: { newIntensity in
                            updateLightIntensity(entityId: entityId, intensity: newIntensity)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    TextInputNumberView(label: "Falloff", value: Binding(
                        get: { falloff },
                        set: { newFalloff in
                            updateLightFalloff(entityId: entityId, falloff: newFalloff)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextInputNumberView(label: "Cone Angle", value: Binding(
                        get: { coneAngle },
                        set: { newConeAngle in
                            updateLightConeAngle(entityId: entityId, coneAngle: newConeAngle)
                            refreshView()
                        }
                    ))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct AreaLightEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Light Property")

        if hasComponent(entityId: entityId, componentType: AreaLightComponent.self) {
            VStack {
                let color: simd_float3 = getLightColor(entityId: entityId)
                let intensity: Float = getLightIntensity(entityId: entityId)
                // add area lights properties here
                TextInputVectorView(label: "Color", value: Binding(
                    get: { color },
                    set: { newColor in
                        updateLightColor(entityId: entityId, color: newColor)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)

                TextInputNumberView(label: "Brightness", value: Binding(
                    get: { intensity },
                    set: { newIntensity in
                        updateLightIntensity(entityId: entityId, intensity: newIntensity)
                        refreshView()
                    }
                ))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct CameraEditorView: View {
    let entityId: EntityID
    let refreshView: () -> Void

    var body: some View {
        Text("Camera System")

        if hasComponent(entityId: entityId, componentType: CameraComponent.self) {
            let eye: simd_float3 = getCameraEye(entityId: entityId)
            let up: simd_float3 = getCameraUp(entityId: entityId)
            let target: simd_float3 = getCameraTarget(entityId: entityId)

            TextInputVectorView(label: "Eye", value: Binding(
                get: { eye },
                set: { newEye in
                    cameraLookAt(entityId: findGameCamera(), eye: newEye, target: target, up: up)
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Up", value: Binding(
                get: { up },
                set: { newUp in
                    cameraLookAt(entityId: findGameCamera(), eye: eye, target: target, up: newUp)
                    refreshView()
                }
            ))

            TextInputVectorView(label: "Target", value: Binding(
                get: { target },
                set: { newTarget in
                    cameraLookAt(entityId: findGameCamera(), eye: eye, target: newTarget, up: up)
                    refreshView()
                }
            ))
        }
    }
}

struct GaussianEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    var body: some View {
        Text("Gaussian Splats")

        HStack(spacing: 12) {
            Text(getAssetURLString(entityId: entityId) ?? " ")
            Button(action: {
                let selectedCategory: AssetCategory = .gaussians
                if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                    let filename = assetPath.deletingPathExtension().lastPathComponent
                    let withExtension = assetPath.pathExtension
                    setEntityGaussian(entityId: entityId, filename: filename, withExtension: withExtension)
                }
                refreshView()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.white)
                    Text("Assign")
                        .fontWeight(.regular)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.editorAccent)
                .foregroundColor(.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}
