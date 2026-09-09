//
//  AssetNodeEditingPolicy.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

func isDerivedAssetNode(_ entityId: EntityID) -> Bool {
    scene.get(component: DerivedAssetNodeComponent.self, for: entityId) != nil
}

func assetRootEntityId(for entityId: EntityID) -> EntityID? {
    scene.get(component: DerivedAssetNodeComponent.self, for: entityId)?.assetRootEntityId
}

func editableAssetRootEntity(for entityId: EntityID) -> EntityID {
    assetRootEntityId(for: entityId) ?? entityId
}

func sceneTransformEntity(for entityId: EntityID) -> EntityID {
    entityId
}

func isAssetInstanceRoot(_ entityId: EntityID) -> Bool {
    scene.get(component: AssetInstanceComponent.self, for: entityId) != nil
}

func canEditSceneTransform(entityId: EntityID) -> Bool {
    hasComponent(entityId: entityId, componentType: LocalTransformComponent.self)
}

func selectableTransformEntity(for entityId: EntityID) -> EntityID {
    let transformEntity = sceneTransformEntity(for: entityId)
    return canEditSceneTransform(entityId: transformEntity) ? transformEntity : .invalid
}

func isBindableAssetMeshNode(_ entityId: EntityID) -> Bool {
    isDerivedAssetNode(entityId)
        && hasComponent(entityId: entityId, componentType: RenderComponent.self)
}

func isAnimationBindingTargetEntity(_ entityId: EntityID) -> Bool {
    hasComponent(entityId: entityId, componentType: SkeletonComponent.self)
        && hasComponent(entityId: entityId, componentType: RenderComponent.self)
}

private func collectAnimationBindingTargets(entityId: EntityID, visited: inout Set<EntityID>) -> [EntityID] {
    guard visited.insert(entityId).inserted else {
        return []
    }

    var targets: [EntityID] = []
    if isAnimationBindingTargetEntity(entityId) {
        targets.append(entityId)
    }

    for childId in getEntityChildren(parentId: entityId) {
        targets.append(contentsOf: collectAnimationBindingTargets(entityId: childId, visited: &visited))
    }

    return targets
}

func editorAnimationBindingTargetEntities(for entityId: EntityID) -> [EntityID] {
    var visited: Set<EntityID> = []
    return collectAnimationBindingTargets(entityId: entityId, visited: &visited)
}

func canAuthorAnimationComponent(entityId: EntityID) -> Bool {
    editorAnimationBindingTargetEntities(for: entityId).isEmpty == false
}

func canShowComponentInInspector(componentType: Any.Type, for entityId: EntityID) -> Bool {
    let key = ObjectIdentifier(componentType)

    if EditorAuthoringMode.sceneCompositionOnly {
        if key == ObjectIdentifier(AnimationComponent.self) {
            return canAuthorAnimationComponent(entityId: entityId)
        }

        if key == ObjectIdentifier(GaussianComponent.self) {
            return hasComponent(entityId: entityId, componentType: GaussianComponent.self)
        }

        if isDerivedAssetNode(entityId) {
            return key == ObjectIdentifier(RenderComponent.self)
                || key == ObjectIdentifier(LocalTransformComponent.self)
        }

        return key == ObjectIdentifier(RenderComponent.self)
            || key == ObjectIdentifier(LocalTransformComponent.self)
            || key == ObjectIdentifier(CameraComponent.self)
            || key == ObjectIdentifier(DirectionalLightComponent.self)
            || key == ObjectIdentifier(PointLightComponent.self)
            || key == ObjectIdentifier(SpotLightComponent.self)
            || key == ObjectIdentifier(AreaLightComponent.self)
    }

    if isDerivedAssetNode(entityId) {
        return key == ObjectIdentifier(AnimationComponent.self)
            && canAuthorAnimationComponent(entityId: entityId)
    }

    if isAssetInstanceRoot(entityId), key == ObjectIdentifier(AnimationComponent.self) {
        return false
    }

    return true
}

func canAddComponentFromInspector(componentType: Any.Type, to entityId: EntityID) -> Bool {
    if EditorAuthoringMode.sceneCompositionOnly {
        let key = ObjectIdentifier(componentType)
        if key == ObjectIdentifier(AnimationComponent.self) {
            return canAuthorAnimationComponent(entityId: entityId)
        }

        return isDerivedAssetNode(entityId) == false
            && (
                key == ObjectIdentifier(CameraComponent.self)
                    || key == ObjectIdentifier(DirectionalLightComponent.self)
                    || key == ObjectIdentifier(PointLightComponent.self)
                    || key == ObjectIdentifier(SpotLightComponent.self)
                    || key == ObjectIdentifier(AreaLightComponent.self)
            )
    }

    return canShowComponentInInspector(componentType: componentType, for: entityId)
}

func canRemoveComponentFromInspector(componentType: Any.Type, from entityId: EntityID) -> Bool {
    if EditorAuthoringMode.sceneCompositionOnly {
        return false
    }

    return canShowComponentInInspector(componentType: componentType, for: entityId)
}
