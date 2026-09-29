//
//  EditorView+Viewport.swift
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
    /// The room the bar of explore mode takes along the top of the viewport.
    static let exploreBarHeight: CGFloat = 60

    /// The viewport panel: the scene tabs along the top in edit mode, then the
    /// Metal view with its overlays.
    var editorSceneViewport: some View {
        VStack(spacing: 0) {
            if experienceMode == .edit {
                SceneTabStripView(
                    sceneCatalog: sceneCatalog,
                    activeSceneURL: editorController?.currentSceneURL,
                    onSelectScene: editor_requestLoadScene,
                    onAddScene: { NotificationCenter.default.post(name: .editorMenuNewScene, object: nil) }
                )
                viewportHeader
            }
            editorMetalView
        }
    }

    private var editorMetalView: some View {
        EditorSceneView(renderer: renderer!)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Asset rows dropped on the Metal view. The MTKView registers no drag
            // types, so AppKit hands the drop to the SwiftUI host and this modifier;
            // the camera and gizmo recognizers never see the drag session.
            .onDrop(of: [AssetDragPayload.contentType], isTargeted: $isViewportDropTargeted) { providers, location in
                editor_dropAssetOnViewport(providers: providers, location: location)
            }
            .overlay {
                if isViewportDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.editorInfo, lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                ViewportOverlaysView(
                    showsEditorOverlays: editor_showsViewportOverlays,
                    showsStats: shouldShowDemoGallery == false && shouldShowPreviewImportGallery == false,
                    showsHints: editor_showsViewportOverlays || (experienceMode == .explore && shouldShowCameraControlHints),
                    topInset: shouldShowExploreSceneOverlay || shouldShowQuickPreviewSceneOverlay ? Self.exploreBarHeight : 0,
                    mode: viewportSettings.interactionMode,
                    hasSelection: editor_showsViewportOverlays && (selectionManager.selectedEntity ?? .invalid) != .invalid,
                    onSelectView: editor_selectProjection
                )
            }
            .overlay(alignment: .top) {
                if experienceMode == .edit, let camera = editor_previewedCamera {
                    ViewportCameraLabel(cameraName: camera.name) {
                        editor_showViewportCamera(.editor)
                    }
                    .padding(.top, 10)
                }
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
            .overlay(alignment: .bottomTrailing) {
                if let dropStatusMessage {
                    DropStatusToast(message: dropStatusMessage, isError: dropStatusIsError)
                        .padding(14)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
}
