//
//  LogConsoleView.swift
//
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import Foundation
import SwiftUI
import UntoldEngine

struct LogConsoleView: View {
    @Binding var searchQuery: String
    @Binding var autoScroll: Bool
    @StateObject private var store = LogStore.shared
    @State private var selectedLevel: LogLevel? = nil
    @State private var clearLog = false

    private func passes(_ e: LogEvent) -> Bool {
        (selectedLevel == nil || e.level == selectedLevel!) &&
            (searchQuery.isEmpty ||
                e.message.localizedCaseInsensitiveContains(searchQuery) ||
                e.category.localizedCaseInsensitiveContains(searchQuery))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollViewReader { proxy in
                List(store.entries.filter(passes)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortTime(e.timestamp))
                            .font(.caption).foregroundColor(.editorTextSecondary)
                            .frame(width: 84, alignment: .leading)

                        Text(e.message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(colorForLevel(e.level))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    .id(e.id)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .listRowBackground(Color.clear)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.editorSurface.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
                .onChange(of: store.entries.last?.id) { _, last in
                    if autoScroll, let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .error: return .editorError
        case .warning: return .editorWarning
        case .info: return .editorTextPrimary
        case .debug: return .editorTextTertiary
        case .test: return Color.editorAccent
        case .none: return .editorTextPrimary
        }
    }

    private func tag(for level: LogLevel) -> String {
        switch level {
        case .error: return "ERROR"
        case .warning: return "WARN"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .test: return "TEST"
        case .none: return ""
        }
    }

    private func badgeColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .editorError
        case .warning: return .editorWarning
        case .info: return .editorInfo
        case .debug: return .editorTextTertiary
        case .test: return .editorSuccess
        case .none: return .clear
        }
    }
}

private func exportLog(_ entries: [LogEvent]) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    let text = entries.map { e in
        "[\(f.string(from: e.timestamp))] [\(e.level)] [\(e.category)] \(e.message) (\(e.file):\(e.line))"
    }.joined(separator: "\n")

    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("EngineLog.txt")
    do {
        try text.data(using: .utf8)?.write(to: url)
        #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    } catch {
        Logger.logError(message: "Failed to export log: \(error)", category: "Logger")
    }
}
