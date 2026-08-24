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
    private var renderer: UntoldRenderer?

    override func setUp() {
        super.setUp()
        originalGameMode = gameMode
        renderer = UntoldRenderer.create()
        XCTAssertNotNil(renderer)
        _ = registerEditorRenderExtension()
    }

    override func tearDown() {
        gameMode = originalGameMode
        RenderExtensionRegistry.shared.unregister(id: EditorRenderExtension.shared.id)
        renderer = nil
        super.tearDown()
    }

    func testRegistrationAddsEditorExtension() {
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

    func testEditorGraphCompilesWithoutCycles() throws {
        gameMode = false
        let (graph, _) = try buildGameModeGraph()

        XCTAssertNoThrow(try topologicalSortGraph(graph: graph))
    }
}
