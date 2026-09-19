//
//  EditorPlayStateTests.swift
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

final class EditorPlayStateTests: XCTestCase {
    func test_resolve_mapsTheRootViewFlags() {
        XCTAssertEqual(EditorPlayState.resolve(isPlaying: false, isPaused: false), .editing)
        XCTAssertEqual(EditorPlayState.resolve(isPlaying: true, isPaused: false), .playing)
        XCTAssertEqual(EditorPlayState.resolve(isPlaying: true, isPaused: true), .paused)
    }

    func test_resolve_pausedWithoutASessionIsEditing() {
        XCTAssertEqual(EditorPlayState.resolve(isPlaying: false, isPaused: true), .editing)
    }

    func test_playButtonStopsOnlyInsideASession() {
        XCTAssertFalse(EditorPlayState.editing.playButtonStops)
        XCTAssertTrue(EditorPlayState.playing.playButtonStops)
        XCTAssertTrue(EditorPlayState.paused.playButtonStops)
    }

    func test_pauseButtonResumesOnlyWhilePaused() {
        XCTAssertFalse(EditorPlayState.editing.pauseButtonResumes)
        XCTAssertFalse(EditorPlayState.playing.pauseButtonResumes)
        XCTAssertTrue(EditorPlayState.paused.pauseButtonResumes)
    }

    func test_stepWaitsForTheEngineFrameStep() {
        XCTAssertFalse(EditorPlayState.stepIsAvailable)
        XCTAssertFalse(EditorPlayState.paused.canStep)
        XCTAssertFalse(EditorPlayState.playing.canStep)
    }
}
