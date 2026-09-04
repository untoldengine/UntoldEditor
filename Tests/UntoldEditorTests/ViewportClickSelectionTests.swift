//
//  ViewportClickSelectionTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  A left click on empty viewport space clears the selection on both the
//  engine side (active entity, gizmo) and the editor side (via the delegate).
//

import AppKit
import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

private final class RecordingSelectionDelegate: SelectionDelegate {
    var clearCount = 0
    var selected: [EntityID] = []

    func didSelectEntity(_ entityId: EntityID) {
        selected.append(entityId)
    }

    func didInspectEntity(_: EntityID) {}
    func didInspectMesh(_: EntityID, meshIndex _: Int) {}
    func didClearSelection() {
        clearCount += 1
    }

    func resetActiveAxis() {}
}

/// A click recogniser that reports a fixed location.
private final class StubClickGesture: NSClickGestureRecognizer {
    override func location(in _: NSView?) -> NSPoint {
        NSPoint(x: 200, y: 150)
    }
}

final class ViewportClickSelectionTests: XCTestCase {
    private var originalScene: Scene!
    private var savedDelegate: SelectionDelegate?
    private var savedController: EditorController?
    private var savedActiveEntity: EntityID!
    private let delegate = RecordingSelectionDelegate()
    private var view: NSView!

    override func setUp() {
        super.setUp()
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }
        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()

        originalScene = scene
        scene = Scene()
        let camera = createEntity()
        createSceneCamera(entityId: camera)

        savedDelegate = selectionDelegate
        savedController = editorController
        savedActiveEntity = activeEntity
        selectionDelegate = delegate
        view = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    }

    override func tearDown() {
        selectionDelegate = savedDelegate
        editorController = savedController
        activeEntity = savedActiveEntity
        scene = originalScene
        super.tearDown()
    }

    func test_clearViewportSelection_dropsActiveEntityAndNotifiesEditor() {
        activeEntity = createEntity()

        InputSystem.shared.clearViewportSelection()

        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertEqual(delegate.clearCount, 1)
        XCTAssertTrue(delegate.selected.isEmpty)
    }

    func test_leftClickOnEmptySpaceClearsSelection() {
        // EditorController installs itself as the delegate; put the recorder back.
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = true
        selectionDelegate = delegate
        activeEntity = createEntity()

        InputSystem.shared.clearSelectionOnEmptyClick(gestureRecognizer: StubClickGesture(), in: view)

        XCTAssertEqual(activeEntity, .invalid)
        XCTAssertEqual(delegate.clearCount, 1)
    }

    func test_leftClickDoesNothingWhileEditorIsDisabled() {
        editorController = EditorController(selectionManager: SelectionManager())
        editorController?.isEnabled = false
        selectionDelegate = delegate
        let selected = createEntity()
        activeEntity = selected

        InputSystem.shared.clearSelectionOnEmptyClick(gestureRecognizer: StubClickGesture(), in: view)

        XCTAssertEqual(activeEntity, selected)
        XCTAssertEqual(delegate.clearCount, 0)
    }
}
