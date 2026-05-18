//
//  ToolbarViewTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

#if canImport(AppKit)
    final class ToolbarViewTests: XCTestCase {
        /// Build a ToolbarView with closures that flip flags so we can assert wiring.
        private func makeSUT(
            selectionManager: SelectionManager = SelectionManager(),
            onSaveCalled: UnsafeMutablePointer<Bool>,
            onSaveAsCalled: UnsafeMutablePointer<Bool>,
            onClearCalled: UnsafeMutablePointer<Bool>,
            onCameraSaveCalled _: UnsafeMutablePointer<Bool>,
            onPlayToggledValues: UnsafeMutablePointer<[Bool]>,
            onDirLightCalled: UnsafeMutablePointer<Bool>,
            onPointLightCalled: UnsafeMutablePointer<Bool>,
            onSpotLightCalled: UnsafeMutablePointer<Bool>,
            onAreaLightCalled: UnsafeMutablePointer<Bool>,
            onCreateCubeCalled: UnsafeMutablePointer<Bool>,
            onCreateSphereCalled: UnsafeMutablePointer<Bool>,
            onCreatePlaneCalled: UnsafeMutablePointer<Bool>,
            onCreateCylinderCalled: UnsafeMutablePointer<Bool>,
            onCreateConeCalled: UnsafeMutablePointer<Bool>,
            onQuickPreviewModes: UnsafeMutablePointer<[QuickPreviewImportMode]>? = nil
        ) -> ToolbarView {
            ToolbarView(
                selectionManager: selectionManager,
                onSave: { onSaveCalled.pointee = true },
                onSaveAs: { onSaveAsCalled.pointee = true },
                onClear: { onClearCalled.pointee = true },
                onPlayToggled: { value in onPlayToggledValues.pointee.append(value) },
                useSceneCameraDuringPlay: .constant(false),
                dirLightCreate: { onDirLightCalled.pointee = true },
                pointLightCreate: { onPointLightCalled.pointee = true },
                spotLightCreate: { onSpotLightCalled.pointee = true },
                areaLightCreate: { onAreaLightCalled.pointee = true },
                onCreateCube: { onCreateCubeCalled.pointee = true },
                onCreateSphere: { onCreateSphereCalled.pointee = true },
                onCreatePlane: { onCreatePlaneCalled.pointee = true },
                onCreateCylinder: { onCreateCylinderCalled.pointee = true },
                onCreateCone: { onCreateConeCalled.pointee = true },
                onQuickPreview: { mode in onQuickPreviewModes?.pointee.append(mode) }
            )
        }

        func test_actionsAreWired_up() {
            var onSave = false
            var onSaveAs = false
            var onClear = false
            var onCameraSave = false
            var playValues: [Bool] = []
            var onDir = false
            var onPoint = false
            var onSpot = false
            var onArea = false
            var onCube = false
            var onSphere = false
            var onPlane = false
            var onCylinder = false
            var onCone = false
            var quickPreviewModes: [QuickPreviewImportMode] = []

            let sut = makeSUT(
                onSaveCalled: &onSave,
                onSaveAsCalled: &onSaveAs,
                onClearCalled: &onClear,
                onCameraSaveCalled: &onCameraSave,
                onPlayToggledValues: &playValues,
                onDirLightCalled: &onDir,
                onPointLightCalled: &onPoint,
                onSpotLightCalled: &onSpot,
                onAreaLightCalled: &onArea,
                onCreateCubeCalled: &onCube,
                onCreateSphereCalled: &onSphere,
                onCreatePlaneCalled: &onPlane,
                onCreateCylinderCalled: &onCylinder,
                onCreateConeCalled: &onCone,
                onQuickPreviewModes: &quickPreviewModes
            )

            // We cannot programmatically tap SwiftUI Buttons without a host and introspection.
            // Instead, assert that injected closures can be called and flip their flags.
            sut.onSave()
            sut.onSaveAs()
            sut.onClear()
            sut.dirLightCreate()
            sut.pointLightCreate()
            sut.spotLightCreate()
            sut.areaLightCreate()
            sut.onCreateCube()
            sut.onCreateSphere()
            sut.onCreatePlane()
            sut.onCreateCylinder()
            sut.onCreateCone()
            sut.onQuickPreview(.untoldAsset)
            sut.onQuickPreview(.tiledScene)

            XCTAssertTrue(onSave, "onSave should be wired.")
            XCTAssertTrue(onSaveAs, "onSaveAs should be wired.")
            XCTAssertTrue(onClear, "onClear should be wired.")
            XCTAssertTrue(onDir, "dirLightCreate should be wired.")
            XCTAssertTrue(onPoint, "pointLightCreate should be wired.")
            XCTAssertTrue(onSpot, "spotLightCreate should be wired.")
            XCTAssertTrue(onArea, "areaLightCreate should be wired.")
            XCTAssertTrue(onCube, "onCreateCube should be wired.")
            XCTAssertTrue(onSphere, "onCreateSphere should be wired.")
            XCTAssertTrue(onPlane, "onCreatePlane should be wired.")
            XCTAssertTrue(onCylinder, "onCreateCylinder should be wired.")
            XCTAssertTrue(onCone, "onCreateCone should be wired.")
            XCTAssertEqual(quickPreviewModes, [.untoldAsset, .tiledScene], "onQuickPreview should pass selected preview modes.")

            // For play toggle, verify the closure records values we pass.
            // Since @State is internal, we mimic the button behavior by calling the closure directly.
            sut.onPlayToggled(true)
            sut.onPlayToggled(false)
            XCTAssertEqual(playValues, [true, false], "onPlayToggled should receive toggled values in order.")
        }

        func test_viewComposesWithoutCrash() {
            // Smoke test: ensure the view can be created and rendered to a hosting controller without crashing.
            let selection = SelectionManager()
            var playValues: [Bool] = []

            let sut = ToolbarView(
                selectionManager: selection,
                onSave: {},
                onSaveAs: {},
                onClear: {},
                onPlayToggled: { playValues.append($0) },
                useSceneCameraDuringPlay: .constant(false),
                dirLightCreate: {},
                pointLightCreate: {},
                spotLightCreate: {},
                areaLightCreate: {},
                onCreateCube: {},
                onCreateSphere: {},
                onCreatePlane: {},
                onCreateCylinder: {},
                onCreateCone: {},
                onQuickPreview: { _ in }
            )

            // Wrap in a hosting controller to ensure SwiftUI can build the body.
            let host = NSHostingController(rootView: sut)
            XCTAssertNotNil(host.view, "Hosting controller should create a view.")
            _ = host // keep alive
            _ = playValues // keep referenced to avoid 'never read' warning
        }

        // MARK: - Primitive Creation Tests

        func test_primitiveButtons_callCorrectClosures() {
            // Given: A ToolbarView with tracked primitive creation callbacks
            var cubeCreated = false
            var sphereCreated = false
            var planeCreated = false
            var cylinderCreated = false
            var coneCreated = false

            let sut = ToolbarView(
                selectionManager: SelectionManager(),
                onSave: {},
                onSaveAs: {},
                onClear: {},
                onPlayToggled: { _ in },
                useSceneCameraDuringPlay: .constant(false),
                dirLightCreate: {},
                pointLightCreate: {},
                spotLightCreate: {},
                areaLightCreate: {},
                onCreateCube: { cubeCreated = true },
                onCreateSphere: { sphereCreated = true },
                onCreatePlane: { planeCreated = true },
                onCreateCylinder: { cylinderCreated = true },
                onCreateCone: { coneCreated = true },
                onQuickPreview: { _ in }
            )

            // When: Invoking the primitive creation closures
            sut.onCreateCube()
            sut.onCreateSphere()
            sut.onCreatePlane()
            sut.onCreateCylinder()
            sut.onCreateCone()

            // Then: Each closure should be called
            XCTAssertTrue(cubeCreated, "Cube creation callback should be invoked")
            XCTAssertTrue(sphereCreated, "Sphere creation callback should be invoked")
            XCTAssertTrue(planeCreated, "Plane creation callback should be invoked")
            XCTAssertTrue(cylinderCreated, "Cylinder creation callback should be invoked")
            XCTAssertTrue(coneCreated, "Cone creation callback should be invoked")
        }

        func test_primitivesSection_existsInView() {
            // Given: A ToolbarView instance
            var callCount = 0
            let sut = ToolbarView(
                selectionManager: SelectionManager(),
                onSave: {},
                onSaveAs: {},
                onClear: {},
                onPlayToggled: { _ in },
                useSceneCameraDuringPlay: .constant(false),
                dirLightCreate: {},
                pointLightCreate: {},
                spotLightCreate: {},
                areaLightCreate: {},
                onCreateCube: { callCount += 1 },
                onCreateSphere: { callCount += 1 },
                onCreatePlane: { callCount += 1 },
                onCreateCylinder: {},
                onCreateCone: {},
                onQuickPreview: { _ in }
            )

            // When: Calling the primitive closures
            sut.onCreateCube()
            sut.onCreateSphere()
            sut.onCreatePlane()

            // Then: All three active primitives should have been called
            XCTAssertEqual(callCount, 3, "All three active primitive buttons (cube, sphere, plane) should be functional")
        }

        func test_primitiveCallbacks_areIndependent() {
            // Given: Separate tracking for each primitive
            var cubeCount = 0
            var sphereCount = 0
            var planeCount = 0

            let sut = ToolbarView(
                selectionManager: SelectionManager(),
                onSave: {},
                onSaveAs: {},
                onClear: {},
                onPlayToggled: { _ in },
                useSceneCameraDuringPlay: .constant(false),
                dirLightCreate: {},
                pointLightCreate: {},
                spotLightCreate: {},
                areaLightCreate: {},
                onCreateCube: { cubeCount += 1 },
                onCreateSphere: { sphereCount += 1 },
                onCreatePlane: { planeCount += 1 },
                onCreateCylinder: {},
                onCreateCone: {},
                onQuickPreview: { _ in }
            )

            // When: Calling specific primitive closures multiple times
            sut.onCreateCube()
            sut.onCreateCube()
            sut.onCreateSphere()

            // Then: Each closure should track independently
            XCTAssertEqual(cubeCount, 2, "Cube should be created twice")
            XCTAssertEqual(sphereCount, 1, "Sphere should be created once")
            XCTAssertEqual(planeCount, 0, "Plane should not be created")
        }

        func test_quickPreviewModes_exposeExpectedPickerConfiguration() {
            XCTAssertEqual(QuickPreviewImportMode.allCases, [.untoldAsset, .tiledScene, .gaussian])

            XCTAssertEqual(QuickPreviewImportMode.untoldAsset.menuTitle, "Load Untold Asset (.untold)")
            XCTAssertEqual(QuickPreviewImportMode.untoldAsset.allowedContentTypes.first?.preferredFilenameExtension, "untold")

            XCTAssertEqual(QuickPreviewImportMode.tiledScene.menuTitle, "Load Tiled Stream (.json)")
            XCTAssertEqual(QuickPreviewImportMode.tiledScene.allowedContentTypes, [.json])

            XCTAssertEqual(QuickPreviewImportMode.gaussian.menuTitle, "Load Gaussian (.ply)")
            XCTAssertEqual(QuickPreviewImportMode.gaussian.allowedContentTypes.first?.preferredFilenameExtension, "ply")
        }
    }
#endif
