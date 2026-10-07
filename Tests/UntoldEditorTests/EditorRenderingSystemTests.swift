//
//  EditorRenderingSystemTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

@MainActor
final class EditorRenderingSystemTests: XCTestCase {
    private var originalGameMode = false
    private var originalActiveCamera: EntityID?
    private var previewCamera: EntityID = .invalid
    private var renderer: UntoldRenderer?

    override func setUp() {
        super.setUp()
        originalGameMode = gameMode
        originalActiveCamera = CameraSystem.shared.activeCamera
        renderer = UntoldRenderer.create()
        XCTAssertNotNil(renderer)
        _ = registerEditorRenderExtension()
        // Editing happens on the editor's camera unless a test says otherwise.
        ViewportCameras.show(.editor)
    }

    override func tearDown() {
        if previewCamera != .invalid {
            destroyEntity(entityId: previewCamera)
            previewCamera = .invalid
        }
        CameraSystem.shared.activeCamera = originalActiveCamera
        gameMode = originalGameMode
        RenderExtensionRegistry.shared.unregister(id: EditorRenderExtension.shared.id)
        renderer = nil
        super.tearDown()
    }

    func testRegistrationAddsEditorMenuPlugin() {
        XCTAssertTrue(
            RenderExtensionRegistry.shared.registeredIDs().contains(EditorRenderExtension.shared.id)
        )
    }

    func testEditModeInjectsEditorPassesBeforeComposite() throws {
        gameMode = false

        let (graph, _) = try buildGameModeGraph()
        let order = try topologicalSortGraph(graph: graph).map(\.id)
        let editorPasses = [
            "untold.editor.highlight",
            "untold.editor.lightVisuals",
            "untold.editor.gizmo",
        ]

        for passID in editorPasses {
            XCTAssertNotNil(graph[passID])
        }

        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: editorPasses[0])), try XCTUnwrap(order.firstIndex(of: editorPasses[1])))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: editorPasses[1])), try XCTUnwrap(order.firstIndex(of: editorPasses[2])))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: editorPasses[2])), try XCTUnwrap(order.firstIndex(of: "precomp")))
    }

    func testPlayModeUsesRuntimeGraphWithoutEditorPasses() throws {
        gameMode = true

        let (graph, _) = try buildGameModeGraph()

        XCTAssertNil(graph["untold.editor.highlight"])
        XCTAssertNil(graph["untold.editor.lightVisuals"])
        XCTAssertNil(graph["untold.editor.gizmo"])
    }

    func testLockedPreviewUsesRuntimeGraphWithoutEditorPasses() throws {
        gameMode = false
        previewCamera = createEntity()
        registerComponent(entityId: previewCamera, componentType: CameraComponent.self)
        XCTAssertTrue(ViewportCameras.show(.game(previewCamera)))

        let (graph, _) = try buildGameModeGraph()

        XCTAssertNil(graph["untold.editor.highlight"])
        XCTAssertNil(graph["untold.editor.lightVisuals"])
        XCTAssertNil(graph["untold.editor.gizmo"])
        // The engine composites the gizmo layer whenever the game is not
        // playing: cleared, nothing of the last editor frame stays on screen.
        XCTAssertNotNil(graph["untold.editor.clearGizmoLayer"])
        let order = try topologicalSortGraph(graph: graph).map(\.id)
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: "untold.editor.clearGizmoLayer")), try XCTUnwrap(order.firstIndex(of: "precomp")))
    }

    func testPausedSessionOnAGameCameraDrawsNoEditorPasses() throws {
        // Paused: the game is not playing, but the session is open and the
        // viewport shows the game's camera.
        gameMode = false
        previewCamera = createEntity()
        registerComponent(entityId: previewCamera, componentType: CameraComponent.self)
        CameraSystem.shared.activeCamera = previewCamera
        let playback = EditorPlaybackSettings(defaults: nil)
        playback.isSessionActive = true
        let originalPlayback = ViewportCameras.playback
        ViewportCameras.playback = playback
        defer { ViewportCameras.playback = originalPlayback }

        let (graph, _) = try buildGameModeGraph()

        XCTAssertNil(graph["untold.editor.highlight"], "drawn from the editor's camera, it would sit in the wrong place")
        XCTAssertNil(graph["untold.editor.lightVisuals"])
        XCTAssertNil(graph["untold.editor.gizmo"])
        XCTAssertNotNil(graph["untold.editor.clearGizmoLayer"])
    }

    func testHeadsetPreviewUsesRuntimeGraphWithOnlyTheClearingPass() throws {
        gameMode = false
        let original = ViewportCameras.isPreviewingOnHeadset
        ViewportCameras.isPreviewingOnHeadset = { true }
        defer { ViewportCameras.isPreviewingOnHeadset = original }

        let (graph, _) = try buildGameModeGraph()

        XCTAssertNil(graph["untold.editor.highlight"])
        XCTAssertNil(graph["untold.editor.lightVisuals"])
        XCTAssertNil(graph["untold.editor.gizmo"])
        XCTAssertNotNil(graph["untold.editor.clearGizmoLayer"], "nothing of the editor's shows in the headset")
    }

    func testEditingAddsNoClearingPassOfItsOwn() throws {
        gameMode = false

        let (graph, _) = try buildGameModeGraph()

        XCTAssertNil(graph["untold.editor.clearGizmoLayer"], "the highlight pass clears the layer itself")
    }

    func testEditorGraphCompilesWithoutCycles() throws {
        gameMode = false
        let (graph, _) = try buildGameModeGraph()

        XCTAssertNoThrow(try topologicalSortGraph(graph: graph))
    }
}
