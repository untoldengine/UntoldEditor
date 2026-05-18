//
//  AssetNodeEditingPolicy.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
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

func canAuthorAnimationComponent(entityId: EntityID) -> Bool {
    if EditorAuthoringMode.sceneCompositionOnly {
        return false
    }

    if isDerivedAssetNode(entityId) {
        return isBindableAssetMeshNode(entityId)
    }

    return isAssetInstanceRoot(entityId) == false
}

func canShowComponentInInspector(componentType: Any.Type, for entityId: EntityID) -> Bool {
    let key = ObjectIdentifier(componentType)

    if EditorAuthoringMode.sceneCompositionOnly {
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
        return isBindableAssetMeshNode(entityId)
            && key == ObjectIdentifier(AnimationComponent.self)
    }

    if isAssetInstanceRoot(entityId), key == ObjectIdentifier(AnimationComponent.self) {
        return false
    }

    return true
}

func canAddComponentFromInspector(componentType: Any.Type, to entityId: EntityID) -> Bool {
    if EditorAuthoringMode.sceneCompositionOnly {
        let key = ObjectIdentifier(componentType)
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
