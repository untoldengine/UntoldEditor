//
//  EditorUndoHistoryTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
import XCTest

/// The undo manager exposes its stacks as names for the toolbar's History
/// popover and the status bar's "Last action".
final class EditorUndoHistoryTests: XCTestCase {
    private var value = 0

    override func setUp() {
        super.setUp()
        EditorUndoManager.shared.clear()
        value = 0
    }

    override func tearDown() {
        EditorUndoManager.shared.clear()
        super.tearDown()
    }

    private func change(_ name: String, to newValue: Int) {
        EditorUndoManager.shared.registerValueChange(name: name, oldValue: value, newValue: newValue) { [self] applied in
            value = applied
        }
        value = newValue
    }

    func test_historyListsTheMostRecentActionFirst() {
        change("Set A", to: 1)
        change("Set B", to: 2)

        XCTAssertEqual(EditorUndoManager.shared.undoHistory, ["Set B", "Set A"])
        XCTAssertEqual(EditorUndoManager.shared.redoHistory, [])
    }

    func test_undoMovesTheActionToTheRedoHistory() {
        change("Set A", to: 1)
        change("Set B", to: 2)

        EditorUndoManager.shared.undo()

        XCTAssertEqual(EditorUndoManager.shared.undoHistory, ["Set A"])
        XCTAssertEqual(EditorUndoManager.shared.redoHistory, ["Set B"])
        XCTAssertEqual(value, 1)
    }

    func test_undoSteps_undoesUpToTheChosenAction() {
        change("Set A", to: 1)
        change("Set B", to: 2)
        change("Set C", to: 3)

        EditorUndoManager.shared.undo(steps: 2)

        XCTAssertEqual(value, 1)
        XCTAssertEqual(EditorUndoManager.shared.undoHistory, ["Set A"])
        XCTAssertEqual(EditorUndoManager.shared.redoHistory, ["Set B", "Set C"])

        EditorUndoManager.shared.redo(steps: 2)

        XCTAssertEqual(value, 3)
        XCTAssertEqual(EditorUndoManager.shared.redoHistory, [])
    }

    func test_clearEmptiesBothHistories() {
        change("Set A", to: 1)
        EditorUndoManager.shared.undo()

        EditorUndoManager.shared.clear()

        XCTAssertEqual(EditorUndoManager.shared.undoHistory, [])
        XCTAssertEqual(EditorUndoManager.shared.redoHistory, [])
    }
}
