//
//  ComponentOptions.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
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

func editorMaterialSlotHoverText(textureType: TextureType, textureURL: URL?) -> String {
    guard let textureURL else {
        return "No \(textureType.displayName) texture assigned"
    }

    let materialName: String
    if let host = textureURL.host, textureURL.scheme == "usdz-embedded", host.isEmpty == false {
        materialName = host
    } else {
        let folderName = textureURL.deletingLastPathComponent().lastPathComponent
        materialName = folderName.isEmpty ? "Unknown" : folderName
    }

    return """
    \(textureType.displayName)
    Material: \(materialName)
    Texture: \(textureURL.lastPathComponent)
    """
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

func shouldHideGenericTransformInspector(entityId: EntityID) -> Bool {
    hasComponent(entityId: entityId, componentType: DirectionalLightComponent.self)
}

func visibleInspectorComponents(
    mergedComponents: [ObjectIdentifier: ComponentOption_Editor],
    entityId: EntityID,
    isInspectedMeshEntity: Bool
) -> [ObjectIdentifier: ComponentOption_Editor] {
    mergedComponents.filter { key, _ in
        if isInspectedMeshEntity, key == ObjectIdentifier(RenderComponent.self) {
            return false
        }

        if shouldHideGenericTransformInspector(entityId: entityId),
           key == ObjectIdentifier(LocalTransformComponent.self)
        {
            return false
        }

        return true
    }
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
