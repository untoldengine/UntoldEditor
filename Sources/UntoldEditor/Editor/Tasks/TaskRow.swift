//
//  TaskRow.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

struct TaskRow: View {
    let task: EditorTask
    let now: Date
    let onCancel: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            statusIcon
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.editorTextPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(trailingLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.editorTextSecondary)
                }

                if task.isActive, let progress = task.progress {
                    ProgressView(value: progress, total: 1)
                        .progressViewStyle(.linear)
                        .tint(Color.editorAccent)
                        .frame(height: 4)
                }

                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.system(size: 11))
                        .foregroundColor(detailColor)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }

            actionButton
                .frame(width: 22)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.editorFill : Color.editorFillSubtle)
        )
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch task.state {
        case .running, .cancelling:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.editorSuccess)
        case .failed:
            Image(systemName: "xmark.octagon.fill")
                .foregroundColor(.editorError)
        case .cancelled:
            Image(systemName: "slash.circle.fill")
                .foregroundColor(.editorTextTertiary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch task.state {
        case .running:
            if task.isCancellable {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(isHovering ? .editorError : .editorTextSecondary)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Cancel this task")
            } else {
                Color.clear
            }
        case .cancelling:
            Image(systemName: "hourglass")
                .font(.system(size: 12))
                .foregroundColor(.editorTextTertiary)
                .help("Waiting for the task to stop")
        case .succeeded, .failed, .cancelled:
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.editorTextTertiary)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .opacity(isHovering ? 1 : 0)
            .help("Remove from list")
        }
    }

    /// Right-aligned label: percentage while a progress-reporting task runs,
    /// otherwise elapsed time (frozen at completion for finished tasks).
    private var trailingLabel: String {
        let elapsed = formatElapsed(task.elapsed(now: now))
        switch task.state {
        case .running:
            if let progress = task.progress {
                return "\(Int((progress * 100).rounded()))% · \(elapsed)"
            }
            return elapsed
        case .cancelling:
            return elapsed
        case .succeeded:
            return "Done in \(elapsed)"
        case .failed:
            return "Failed after \(elapsed)"
        case .cancelled:
            return "Cancelled after \(elapsed)"
        }
    }

    private var detailColor: Color {
        switch task.state {
        case .failed: return .editorError
        case .cancelled: return .editorTextTertiary
        case .running, .cancelling, .succeeded: return .editorTextSecondary
        }
    }

    private func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
