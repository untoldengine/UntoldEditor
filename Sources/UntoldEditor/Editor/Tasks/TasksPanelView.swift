//
//  TasksPanelView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Bottom-dock "Tasks" panel: every background job registered with
//  `TaskCenter`, with a progress bar (when the job reports progress) or a
//  spinner plus elapsed time, and a cancel button for jobs that support it.
//

import SwiftUI

struct TasksPanelView: View {
    @Binding var searchQuery: String
    @ObservedObject private var center = TaskCenter.shared
    /// Ticks once a second so elapsed-time labels advance while tasks run.
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var visibleTasks: [EditorTask] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? center.tasks
            : center.tasks.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                    $0.detail.localizedCaseInsensitiveContains(query)
            }
        // Running first (newest on top), then finished (newest on top).
        let active = filtered.filter(\.isActive).reversed()
        let finished = filtered.filter { !$0.isActive }.reversed()
        return Array(active) + Array(finished)
    }

    var body: some View {
        Group {
            if visibleTasks.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(visibleTasks) { task in
                            TaskRow(task: task, now: now) {
                                center.cancel(task.id)
                            } onDismiss: {
                                center.remove(task.id)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.editorSurface.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .padding(8)
        .onReceive(clock) { now = $0 }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 22))
                .foregroundColor(.editorTextTertiary)
            Text(searchQuery.isEmpty ? "No background tasks" : "No tasks match “\(searchQuery)”")
                .font(.system(size: 12))
                .foregroundColor(.editorTextSecondary)
            if searchQuery.isEmpty {
                Text("Asset exports, Gaussian cooks, script builds and scene loads show up here.")
                    .font(.system(size: 11))
                    .foregroundColor(.editorTextTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
