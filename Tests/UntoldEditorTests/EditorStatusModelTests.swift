//
//  EditorStatusModelTests.swift
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

final class EditorStatusModelTests: XCTestCase {
    func test_readiness_prefersTheRestoreThenRunningTasks() {
        XCTAssertEqual(EditorStatusModel.readiness(activeTasks: 0, isRestoringPlayMode: false), .init(label: "Ready", isBusy: false))
        XCTAssertEqual(EditorStatusModel.readiness(activeTasks: 1, isRestoringPlayMode: false), .init(label: "1 task running", isBusy: true))
        XCTAssertEqual(EditorStatusModel.readiness(activeTasks: 3, isRestoringPlayMode: false), .init(label: "3 tasks running", isBusy: true))
        XCTAssertEqual(EditorStatusModel.readiness(activeTasks: 3, isRestoringPlayMode: true), .init(label: "Restoring scene", isBusy: true))
    }

    func test_fps_roundsTheSmoothedFrameTime() {
        XCTAssertEqual(EditorStatusModel.fps(frameMs: 16.13), "62 fps")
        XCTAssertEqual(EditorStatusModel.fps(frameMs: 8.333), "120 fps")
        XCTAssertEqual(EditorStatusModel.fps(frameMs: 0), "— fps")
    }

    func test_counts_pluralise() {
        XCTAssertEqual(EditorStatusModel.drawCalls(1), "1 draw call")
        XCTAssertEqual(EditorStatusModel.drawCalls(3), "3 draw calls")
        XCTAssertEqual(EditorStatusModel.entities(1), "1 entity")
        XCTAssertEqual(EditorStatusModel.entities(5), "5 entities")
    }

    func test_gpuMemory_readsInMegabytes() {
        XCTAssertEqual(EditorStatusModel.gpuMemory(bytes: 212 * 1_048_576), "GPU 212 MB")
        XCTAssertEqual(EditorStatusModel.gpuMemory(bytes: 1_572_864), "GPU 1.5 MB")
        XCTAssertEqual(EditorStatusModel.gpuMemory(bytes: 0), "GPU —")
    }

    func test_lastAction_namesTheUndoableActionOrNone() {
        XCTAssertEqual(EditorStatusModel.lastAction("Move Entity_7"), "Last action: Move Entity_7")
        XCTAssertEqual(EditorStatusModel.lastAction(nil), "Last action: none")
    }

    func test_saveState_unsavedEditsWin() {
        let state = EditorStatusModel.saveState(isDirty: true, hasSceneFile: true, lastSavedAt: Date())
        XCTAssertEqual(state, .init(label: "Unsaved changes", isUnsaved: true))
    }

    func test_saveState_showsTheTimeOfTheLastSave() {
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = "Saved \(EditorStatusModel.timeFormatter.string(from: savedAt))"
        XCTAssertEqual(EditorStatusModel.saveState(isDirty: false, hasSceneFile: true, lastSavedAt: savedAt), .init(label: expected, isUnsaved: false))
    }

    func test_saveState_withoutAFileOrATime() {
        XCTAssertEqual(EditorStatusModel.saveState(isDirty: false, hasSceneFile: true, lastSavedAt: nil), .init(label: "Saved", isUnsaved: false))
        XCTAssertEqual(EditorStatusModel.saveState(isDirty: false, hasSceneFile: false, lastSavedAt: nil), .init(label: "Not saved yet", isUnsaved: true))
    }
}
