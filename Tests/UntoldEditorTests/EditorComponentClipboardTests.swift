//
//  EditorComponentClipboardTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// The Inspector's Copy, Paste and Reset for the transform, and its pin.
final class EditorComponentClipboardTests: XCTestCase {
    override func setUp() {
        super.setUp()
        scene = Scene()
        EditorUndoManager.shared.clear()
        EditorComponentClipboard.shared.clear()
    }

    override func tearDown() {
        EditorUndoManager.shared.clear()
        EditorComponentClipboard.shared.clear()
        super.tearDown()
    }

    private func entityWithTransform() -> EntityID {
        let entity = createEntity()
        registerComponent(entityId: entity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: entity, componentType: WorldTransformComponent.self)
        return entity
    }

    func test_copyThenPaste_carriesTheTransform_asOneUndoStep() {
        let source = entityWithTransform()
        let target = entityWithTransform()
        translateTo(entityId: source, position: simd_float3(1, 2, 3))
        scaleTo(entityId: source, scale: simd_float3(2, 2, 2))

        EditorComponentClipboard.shared.copyTransform(of: source)
        XCTAssertTrue(EditorComponentClipboard.shared.pasteTransform(into: target))

        XCTAssertEqual(getLocalPosition(entityId: target), simd_float3(1, 2, 3))
        XCTAssertEqual(getScale(entityId: target), simd_float3(2, 2, 2))
        XCTAssertTrue(EditorUndoManager.shared.canUndo)

        EditorUndoManager.shared.undo()
        XCTAssertEqual(getLocalPosition(entityId: target), simd_float3(0, 0, 0))
    }

    func test_paste_withNothingCopied_doesNothing() {
        let target = entityWithTransform()
        XCTAssertFalse(EditorComponentClipboard.shared.pasteTransform(into: target))
        XCTAssertFalse(EditorUndoManager.shared.canUndo)
    }

    func test_resetTransform_isOneUndoStep() {
        let entity = entityWithTransform()
        translateTo(entityId: entity, position: simd_float3(4, 5, 6))
        scaleTo(entityId: entity, scale: simd_float3(3, 3, 3))

        resetTransform(entityId: entity)

        XCTAssertEqual(getLocalPosition(entityId: entity), simd_float3(0, 0, 0))
        XCTAssertEqual(getScale(entityId: entity), simd_float3(1, 1, 1))
        XCTAssertTrue(EditorUndoManager.shared.canUndo)

        EditorUndoManager.shared.undo()
        XCTAssertEqual(getLocalPosition(entityId: entity), simd_float3(4, 5, 6))
    }

    func test_pin_keepsTheInspectedEntityWhileTheSelectionChanges() {
        let manager = SelectionManager()
        let pinned = entityWithTransform()
        let other = entityWithTransform()

        manager.togglePinnedInspection(pinned)
        manager.selectedEntity = other
        XCTAssertEqual(manager.pinnedInspection, pinned)

        manager.togglePinnedInspection(pinned)
        XCTAssertNil(manager.pinnedInspection)
    }
}
