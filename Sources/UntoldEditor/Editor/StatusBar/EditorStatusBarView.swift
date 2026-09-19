//
//  EditorStatusBarView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The 24 pt bar under the window: readiness, frame rate, draw calls, entity
/// count and GPU memory on the left; the last undoable action, the build target
/// and the scene's save state on the right.
struct EditorStatusBarView: View {
    static let height: CGFloat = 24

    let entityCount: Int
    let hasSceneFile: Bool
    let isRestoringPlayMode: Bool

    @ObservedObject private var stats = EditorEngineStatsStore.shared
    @ObservedObject private var tasks = TaskCenter.shared
    @ObservedObject private var undoManager = EditorUndoManager.shared
    @ObservedObject private var dirtyState = EditorSceneDirtyState.shared
    @ObservedObject private var buildTarget = EditorBuildTargetSettings.shared

    init(entityCount: Int, hasSceneFile: Bool, isRestoringPlayMode: Bool) {
        self.entityCount = entityCount
        self.hasSceneFile = hasSceneFile
        self.isRestoringPlayMode = isRestoringPlayMode
    }

    var body: some View {
        let readiness = EditorStatusModel.readiness(activeTasks: tasks.activeCount, isRestoringPlayMode: isRestoringPlayMode)
        let saveState = EditorStatusModel.saveState(
            isDirty: dirtyState.isDirty,
            hasSceneFile: hasSceneFile,
            lastSavedAt: dirtyState.lastSavedAt
        )
        return HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(readiness.isBusy ? Color.editorAccent : Color.editorSuccess)
                    .frame(width: 7, height: 7)
                Text(readiness.label)
            }
            Text(EditorStatusModel.fps(frameMs: stats.snapshot.timing.smoothedFrameMs))
                .font(EditorType.mono)
            Text(EditorStatusModel.drawCalls(stats.snapshot.render.drawCallsTotal))
                .font(EditorType.mono)
            Text(EditorStatusModel.entities(entityCount))
                .font(EditorType.mono)
            Text(EditorStatusModel.gpuMemory(bytes: stats.snapshot.memory.meshMemoryBytes + stats.snapshot.memory.textureMemoryBytes))
                .font(EditorType.mono)
            Spacer(minLength: 12)
            Text(EditorStatusModel.lastAction(undoManager.undoHistory.first))
                .lineLimit(1)
            Text("Target: \(buildTarget.target.statusLabel)")
            HStack(spacing: 6) {
                Circle()
                    .fill(saveState.isUnsaved ? Color.editorAccent : Color.editorSuccess)
                    .frame(width: 7, height: 7)
                Text(saveState.label)
                    .foregroundColor(saveState.isUnsaved ? .editorAccent : .editorTextSecondary)
            }
        }
        .font(EditorType.hint)
        .foregroundColor(.editorTextSecondary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color.editorBarDark)
    }
}
