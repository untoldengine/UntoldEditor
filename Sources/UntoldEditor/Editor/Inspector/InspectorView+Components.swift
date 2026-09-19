//
//  InspectorView+Components.swift
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

extension InspectorView {
    func addComponentToEntity_Editor(componentType: Any.Type) {
        guard let entityId = selectionManager.selectedEntity else { return }
        guard canAddComponentFromInspector(componentType: componentType, to: entityId) else { return }

        EditorSceneDirtyState.shared.markDirty()
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

        EditorSceneDirtyState.shared.markDirty()
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
            removeEntityGaussian(entityId: entityId)
            EditorGaussianAssetState.shared.clear(entityId: entityId)
        } else if key == ObjectIdentifier(ScriptComponent.self) {
            scene.remove(component: ScriptComponent.self, from: entityId)
        } else if key == ObjectIdentifier(LODComponent.self) {
            scene.remove(component: LODComponent.self, from: entityId)
        }

        refreshView()
    }

    func refreshView() {
        selectionManager.objectWillChange.send()
        sceneGraphModel.refreshHierarchy()
    }

    func availableComponentsWithFlags() -> [ComponentOption_Editor] {
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
