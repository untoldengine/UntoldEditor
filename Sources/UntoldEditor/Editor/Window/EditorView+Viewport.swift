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
    var editorSceneViewport: some View {
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
            .overlay(alignment: .topLeading) {
                EngineStatsOverlayView()
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
            .overlay(alignment: .bottom) {
                if shouldShowCameraControlHints {
                    CameraControlHintsView {
                        dismissCameraControlHints()
                    }
                    .padding(.bottom, 14)
                }
            }
            .overlay(alignment: .top) {
                if experienceMode == .edit, let controller = editorController {
                    TransformModeCluster(controller: controller)
                        .padding(.top, 12)
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
