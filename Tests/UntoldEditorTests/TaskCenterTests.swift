//
//  TaskCenterTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
@testable import UntoldEditor
import XCTest

@MainActor
final class TaskCenterTests: XCTestCase {
    private var center: TaskCenter {
        TaskCenter.shared
    }

    override func setUp() async throws {
        try await super.setUp()
        await settle()
        center.removeAllForTesting()
    }

    /// TaskCenter hops every mutation onto the main actor via `Task {}`; yield
    /// a few times so those enqueued jobs land before we assert.
    private func settle() async {
        for _ in 0 ..< 5 {
            await Task.yield()
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }

    private func task(_ id: UUID) -> EditorTask? {
        center.tasks.first { $0.id == id }
    }

    func test_begin_registersRunningIndeterminateTask() async {
        let handle = TaskCenter.begin("Export thing", detail: "d")
        await settle()

        let t = task(handle.id)
        XCTAssertNotNil(t)
        XCTAssertEqual(t?.title, "Export thing")
        XCTAssertEqual(t?.detail, "d")
        XCTAssertEqual(t?.state, .running)
        XCTAssertNil(t?.progress)
        XCTAssertFalse(t?.isCancellable ?? true)
        XCTAssertEqual(center.activeCount, 1)
    }

    func test_progressUpdates_clampAndConvertCounts() async {
        let handle = TaskCenter.begin("Progress")
        handle.setProgress(current: 3, total: 4)
        await settle()
        XCTAssertEqual(task(handle.id)?.progress ?? -1, 0.75, accuracy: 0.0001)

        handle.setProgress(1.7)
        await settle()
        XCTAssertEqual(task(handle.id)?.progress, 1)

        handle.setProgress(current: 2, total: 0)
        await settle()
        XCTAssertNil(task(handle.id)?.progress, "zero total means indeterminate")
    }

    func test_succeed_freezesElapsedAndDropsCancellability() async {
        var cancelCalls = 0
        let handle = TaskCenter.begin("Job", onCancel: { cancelCalls += 1 })
        await settle()
        XCTAssertTrue(task(handle.id)?.isCancellable ?? false)

        handle.succeed("done")
        await settle()

        let t = task(handle.id)
        XCTAssertEqual(t?.state, .succeeded)
        XCTAssertEqual(t?.detail, "done")
        XCTAssertNotNil(t?.finishedAt)
        XCTAssertFalse(t?.isCancellable ?? true)
        XCTAssertEqual(center.activeCount, 0)

        // Cancelling a finished task is a no-op.
        center.cancel(handle.id)
        await settle()
        XCTAssertEqual(cancelCalls, 0)
        XCTAssertEqual(task(handle.id)?.state, .succeeded)
    }

    func test_cancel_runsHookAndMovesToCancelling_thenJobConfirms() async {
        var cancelCalls = 0
        let handle = TaskCenter.begin("Cancellable", onCancel: { cancelCalls += 1 })
        await settle()

        center.cancel(handle.id)
        await settle()

        XCTAssertEqual(cancelCalls, 1)
        XCTAssertTrue(handle.isCancelRequested)
        XCTAssertEqual(task(handle.id)?.state, .cancelling)
        XCTAssertEqual(center.activeCount, 1, "still active until the job confirms it stopped")

        handle.finish(processStatus: 15)
        await settle()
        XCTAssertEqual(task(handle.id)?.state, .cancelled, "cancel request wins over exit status")
        XCTAssertEqual(center.activeCount, 0)
    }

    func test_setCancelHandler_afterCancelRequested_firesImmediately() async {
        let handle = TaskCenter.begin("Late process", onCancel: {})
        await settle()
        center.cancel(handle.id)
        await settle()

        var lateHandlerCalls = 0
        handle.setCancelHandler { lateHandlerCalls += 1 }
        XCTAssertEqual(lateHandlerCalls, 1, "a Process created after the user hit cancel must still be terminated")
    }

    func test_finishProcessStatus_mapsExitCodes() async {
        let ok = TaskCenter.begin("ok")
        let bad = TaskCenter.begin("bad")
        ok.finish(processStatus: 0, successDetail: "wrote file")
        bad.finish(processStatus: 2)
        await settle()

        XCTAssertEqual(task(ok.id)?.state, .succeeded)
        XCTAssertEqual(task(ok.id)?.detail, "wrote file")
        XCTAssertEqual(task(bad.id)?.state, .failed)
        XCTAssertEqual(task(bad.id)?.detail, "Exited with status 2")
    }

    func test_track_marksSuccessAndFailureFromThrowingBody() async {
        struct Boom: Error {}
        let value = TaskCenter.track("sync work") { _ in 42 }
        XCTAssertEqual(value, 42)

        XCTAssertThrowsError(try TaskCenter.track("failing work") { _ in throw Boom() })
        await settle()

        let states = center.tasks.map(\.state)
        XCTAssertTrue(states.contains(.succeeded))
        XCTAssertTrue(states.contains(.failed))
    }

    func test_clearFinished_and_remove_onlyTouchFinishedTasks() async {
        let running = TaskCenter.begin("running")
        let done = TaskCenter.begin("done")
        done.succeed()
        await settle()

        center.remove(running.id)
        XCTAssertNotNil(task(running.id), "running tasks can't be removed")

        center.clearFinished()
        XCTAssertNil(task(done.id))
        XCTAssertNotNil(task(running.id))

        running.fail("x")
        await settle()
        center.remove(running.id)
        XCTAssertNil(task(running.id))
    }

    func test_elapsed_freezesAtFinish() async {
        let handle = TaskCenter.begin("timed")
        handle.succeed()
        await settle()
        guard let t = task(handle.id) else { return XCTFail("missing task") }
        let a = t.elapsed(now: Date().addingTimeInterval(10))
        let b = t.elapsed(now: Date().addingTimeInterval(20))
        XCTAssertEqual(a, b, accuracy: 0.0001, "finished tasks report a fixed duration")
    }
}
