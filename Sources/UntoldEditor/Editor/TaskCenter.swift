//
//  TaskCenter.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Central registry of long-running editor work (asset exports, Gaussian
//  cooks, script builds, engine asset loads…). The Tasks panel in the bottom
//  dock observes `TaskCenter.shared`; jobs get an `EditorTaskHandle` they can
//  update from any thread and (optionally) a cancel hook the user can trigger.
//

import Combine
import Foundation
import SwiftUI
import UntoldEngine

/// One tracked background job.
struct EditorTask: Identifiable, Equatable {
    enum State: Equatable {
        case running
        case cancelling
        case succeeded
        case failed
        case cancelled

        var isFinished: Bool {
            switch self {
            case .running, .cancelling: return false
            case .succeeded, .failed, .cancelled: return true
            }
        }
    }

    let id: UUID
    var title: String
    /// Short secondary line: current phase, file name, error text…
    var detail: String
    /// 0…1 when the job reports progress, `nil` for indeterminate (spinner).
    var progress: Double?
    var state: State = .running
    let startedAt: Date
    var finishedAt: Date?
    var isCancellable: Bool

    var isActive: Bool {
        !state.isFinished
    }

    /// Elapsed wall time; freezes once the task finishes.
    func elapsed(now: Date = Date()) -> TimeInterval {
        (finishedAt ?? now).timeIntervalSince(startedAt)
    }
}

/// Handle given to the code that runs a job. All methods are thread-safe and
/// hop to the main actor internally, so they can be called from
/// `DispatchQueue.global` closures or `Process` callbacks.
final class EditorTaskHandle: @unchecked Sendable {
    let id: UUID
    private let lock = NSLock()
    private var cancelHandler: (() -> Void)?
    private var _isCancelRequested = false

    fileprivate init(id: UUID, onCancel: (() -> Void)?) {
        self.id = id
        cancelHandler = onCancel
    }

    /// True once the user asked for cancellation. Long loops that can't be
    /// interrupted externally should poll this and bail out.
    var isCancelRequested: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isCancelRequested
    }

    /// Replace the cancel hook after the fact (e.g. once a `Process` has been
    /// created). Passing `nil` makes the task non-cancellable.
    func setCancelHandler(_ handler: (() -> Void)?) {
        lock.lock()
        cancelHandler = handler
        let alreadyRequested = _isCancelRequested
        lock.unlock()
        TaskCenter.shared.update(id) { $0.isCancellable = handler != nil }
        // If the user hit cancel before the process existed, honour it now.
        if alreadyRequested {
            handler?()
        }
    }

    /// Register a `Process` so cancel terminates it. Convenience over
    /// `setCancelHandler`.
    func attach(process: Process) {
        setCancelHandler { [weak process] in
            guard let process, process.isRunning else { return }
            process.terminate()
        }
    }

    func setProgress(_ value: Double?) {
        TaskCenter.shared.update(id) { $0.progress = value.map { min(max($0, 0), 1) } }
    }

    func setProgress(current: Int, total: Int) {
        guard total > 0 else { setProgress(nil); return }
        setProgress(Double(current) / Double(total))
    }

    func setDetail(_ text: String) {
        TaskCenter.shared.update(id) { $0.detail = text }
    }

    func setTitle(_ text: String) {
        TaskCenter.shared.update(id) { $0.title = text }
    }

    func succeed(_ detail: String? = nil) {
        finish(.succeeded, detail: detail)
    }

    func fail(_ detail: String? = nil) {
        finish(.failed, detail: detail)
    }

    /// Mark the task as cancelled (call from the job once it has actually
    /// stopped). If cancellation was never requested this still records the
    /// task as cancelled.
    func markCancelled(_ detail: String? = nil) {
        finish(.cancelled, detail: detail)
    }

    /// Resolve the terminal state from a `Process` exit: cancelled if the user
    /// asked for it, otherwise success/failure from the exit code.
    func finish(processStatus: Int32, successDetail: String? = nil, failureDetail: String? = nil) {
        if isCancelRequested {
            markCancelled()
        } else if processStatus == 0 {
            succeed(successDetail)
        } else {
            fail(failureDetail ?? "Exited with status \(processStatus)")
        }
    }

    private func finish(_ state: EditorTask.State, detail: String?) {
        TaskCenter.shared.update(id) { task in
            guard task.isActive else { return }
            task.state = state
            task.finishedAt = Date()
            task.isCancellable = false
            if state == .succeeded {
                task.progress = task.progress == nil ? nil : 1
            }
            if let detail {
                task.detail = detail
            }
        }
    }

    /// Invoked by the Tasks panel. Flips the task to `.cancelling` and runs the
    /// job's cancel hook; the job is expected to call `markCancelled` (or
    /// `finish(processStatus:)`) once it has stopped.
    fileprivate func requestCancel() {
        lock.lock()
        _isCancelRequested = true
        let handler = cancelHandler
        lock.unlock()
        TaskCenter.shared.update(id) { task in
            guard task.state == .running else { return }
            task.state = .cancelling
            task.detail = "Cancelling…"
        }
        handler?()
    }
}

/// Store the Tasks panel observes. `tasks` is only ever mutated on the main
/// actor (every entry point hops there), so SwiftUI observation stays safe
/// while jobs can report from any thread.
final class TaskCenter: ObservableObject, @unchecked Sendable {
    static let shared = TaskCenter()

    @Published private(set) var tasks: [EditorTask] = []

    /// Finished tasks are kept so the user can see results/errors; oldest are
    /// dropped beyond this many.
    private let maxFinishedTasks = 50
    private var handles: [UUID: EditorTaskHandle] = [:]

    private init() {}

    @MainActor var activeTasks: [EditorTask] {
        tasks.filter(\.isActive)
    }

    @MainActor var activeCount: Int {
        tasks.reduce(0) { $0 + ($1.isActive ? 1 : 0) }
    }

    /// Start tracking a job. Safe to call from any thread.
    ///
    /// - Parameters:
    ///   - title: What the job is ("Exporting robot.usdz").
    ///   - detail: Optional secondary text.
    ///   - progress: Initial progress, or `nil` for a spinner.
    ///   - onCancel: If non-nil the row shows a cancel button that runs this.
    @discardableResult
    static func begin(
        _ title: String,
        detail: String = "",
        progress: Double? = nil,
        onCancel: (() -> Void)? = nil
    ) -> EditorTaskHandle {
        let id = UUID()
        let handle = EditorTaskHandle(id: id, onCancel: onCancel)
        let task = EditorTask(
            id: id,
            title: title,
            detail: detail,
            progress: progress,
            startedAt: Date(),
            isCancellable: onCancel != nil
        )
        Task { @MainActor in
            shared.tasks.append(task)
            shared.handles[id] = handle
            shared.trimFinished()
        }
        return handle
    }

    /// Convenience for a job that is only tracked (no cancel hook).
    static func track<T>(_ title: String, detail: String = "", _ body: (EditorTaskHandle) throws -> T) rethrows -> T {
        let handle = begin(title, detail: detail)
        do {
            let result = try body(handle)
            handle.succeed()
            return result
        } catch {
            handle.fail(error.localizedDescription)
            throw error
        }
    }

    func update(_ id: UUID, _ mutate: @escaping (inout EditorTask) -> Void) {
        Task { @MainActor in
            guard let index = self.tasks.firstIndex(where: { $0.id == id }) else { return }
            mutate(&self.tasks[index])
            if self.tasks[index].state.isFinished {
                self.handles[id] = nil
            }
        }
    }

    @MainActor func cancel(_ id: UUID) {
        handles[id]?.requestCancel()
    }

    @MainActor func cancelAll() {
        for task in tasks where task.state == .running {
            cancel(task.id)
        }
    }

    @MainActor func remove(_ id: UUID) {
        guard let task = tasks.first(where: { $0.id == id }), task.state.isFinished else { return }
        tasks.removeAll { $0.id == id }
    }

    @MainActor func clearFinished() {
        tasks.removeAll { $0.state.isFinished }
    }

    /// Drops every task and handle without running cancel hooks. Test hook.
    @MainActor func removeAllForTesting() {
        tasks.removeAll()
        handles.removeAll()
    }

    @MainActor private func trimFinished() {
        var finishedCount = tasks.reduce(0) { $0 + ($1.state.isFinished ? 1 : 0) }
        guard finishedCount > maxFinishedTasks else { return }
        tasks.removeAll { task in
            guard task.state.isFinished, finishedCount > maxFinishedTasks else { return false }
            finishedCount -= 1
            return true
        }
    }
}

/// Mirrors the engine's `AssetLoadingState` (scene/model loads that report
/// mesh progress) into the Task Center so they show alongside editor jobs.
/// One task per loading entity; polled because the engine state is an actor.
@MainActor
final class EngineLoadTaskBridge {
    static let shared = EngineLoadTaskBridge()

    private var handles: [EntityID: EditorTaskHandle] = [:]
    private var timer: Timer?

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        Task {
            let progress = await AssetLoadingState.shared.getAllProgress()
            await MainActor.run { self.sync(progress) }
        }
    }

    private func sync(_ progress: [LoadingProgress]) {
        var seen = Set<EntityID>()
        for entry in progress {
            seen.insert(entry.entityId)
            let handle: EditorTaskHandle
            if let existing = handles[entry.entityId] {
                handle = existing
            } else {
                handle = TaskCenter.begin("Loading \(entry.filename)")
                handles[entry.entityId] = handle
            }
            handle.setDetail(entry.totalMeshes > 0
                ? "\(entry.phaseDescription) · \(entry.currentMesh)/\(entry.totalMeshes)"
                : entry.phaseDescription)
            handle.setProgress(current: entry.currentMesh, total: entry.totalMeshes)
        }
        for (entityId, handle) in handles where !seen.contains(entityId) {
            handle.succeed()
            handles[entityId] = nil
        }
    }
}
