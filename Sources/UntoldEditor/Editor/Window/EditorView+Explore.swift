//
//  EditorView+Explore.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    func completeDemoSceneAuthoredLoad(
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
        NotificationCenter.default.post(name: .editorPostFXStateDidChange, object: nil)
        completion(importedCamera != nil)
    }

    var shouldShowDemoGallery: Bool {
        showWelcomeStart
            && showDemoGallery
            && showPreviewImportGallery == false
            && experienceMode == .explore
            && editorBasePath.basePath == nil
    }

    var shouldShowPreviewImportGallery: Bool {
        showWelcomeStart
            && showPreviewImportGallery
            && experienceMode == .explore
            && editorBasePath.basePath == nil
    }

    var shouldShowExploreSceneOverlay: Bool {
        experienceMode == .explore
            && showDemoGallery == false
            && showPreviewImportGallery == false
            && activeDemoScene != nil
    }

    var shouldShowQuickPreviewSceneOverlay: Bool {
        experienceMode == .explore
            && showDemoGallery == false
            && showPreviewImportGallery == false
            && activePreviewSceneTitle != nil
    }

    var shouldShowCameraControlHints: Bool {
        showCameraControlHints
            && shouldShowDemoGallery == false
            && (hasQuickPreviewContent() || activeDemoScene != nil)
    }

    func hasQuickPreviewContent() -> Bool {
        getAllGameEntities().contains { entityId in
            hasComponent(entityId: entityId, componentType: QuickPreviewComponent.self)
        }
    }

    func revealCameraControlHintsIfNeeded() {
        guard cameraControlHintsDismissed == false else {
            return
        }

        showCameraControlHints = true
    }

    func dismissCameraControlHints() {
        cameraControlHintsDismissed = true
        showCameraControlHints = false
    }

    func syncEditorAvailabilityForExperienceMode() {
        editorController?.isEnabled = experienceMode == .edit

        if experienceMode == .explore {
            enableExploreNavigationMode()
            clearExploreSelection()
        } else {
            disableExploreNavigationMode()
        }
    }

    func switchToEditMode() {
        experienceMode = .edit
        showDemoGallery = false
        showPreviewImportGallery = false
        disableExploreNavigationMode()
    }

    func createProjectFromExplore() {
        switchToEditMode()
        showWelcomeStart = false
        showCreateProject = true
    }

    func openProjectFromExplore() {
        switchToEditMode()
        showWelcomeStart = false
        openExistingProjectFromWelcome()
    }

    func showDemoChooser() {
        experienceMode = .explore
        showDemoGallery = true
        showPreviewImportGallery = false
        activePreviewSceneTitle = nil
        activePreviewImportMode = nil
        showCameraControlHints = false
        enableExploreNavigationMode()
    }

    func showPreviewImportChooser() {
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

    func loadCustomPreviewScene(mode: QuickPreviewImportMode) {
        showDemoGallery = false
        showPreviewImportGallery = false
        activeDemoScene = nil
        activeDemoCameraFrame = nil
        enableExploreNavigationMode()
        editor_handleQuickPreview(mode: mode, fromExploreMode: true)
    }

    func resetActiveDemoCamera() {
        guard let activeDemoCameraFrame else {
            return
        }

        applyCameraFrame(activeDemoCameraFrame)
    }
}
