//
//  LogConsoleView.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import Combine
import Foundation
import SwiftUI
import UntoldEngine

struct LogConsoleView: View {
    @StateObject private var store = LogStore.shared
    @State private var selectedLevel: LogLevel? = nil
    @State private var search = ""
    @State private var autoScroll = true
    @State private var clearLog = false

    private func passes(_ e: LogEvent) -> Bool {
        (selectedLevel == nil || e.level == selectedLevel!) &&
            (search.isEmpty ||
                e.message.localizedCaseInsensitiveContains(search) ||
                e.category.localizedCaseInsensitiveContains(search))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Console")
                    .font(.title3)
                    .bold()
                    .foregroundColor(.primary)
                Spacer()
                TextField("Search…", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Toggle("Auto‑scroll", isOn: $autoScroll)
                    .toggleStyle(.checkbox)

                Toggle("Clear", isOn: $clearLog)
                    .toggleStyle(.checkbox)
                    .onChange(of: clearLog) { _, newValue in
                        if newValue {
                            LogStore.shared.clear()
                            clearLog = false
                        }
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            ScrollViewReader { proxy in
                List(store.entries.filter(passes)) { e in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(shortTime(e.timestamp))
                            .font(.caption).foregroundColor(.secondary)
                            .frame(width: 84, alignment: .leading)

//                        Text("[\(e.category)]")
//                            .font(.caption).foregroundColor(.secondary)
//                            .frame(width: 120, alignment: .leading)
//
//                        Text(tag(for: e.level))
//                            .font(.caption2)
//                            .padding(.horizontal, 6).padding(.vertical, 2)
//                            .background(badgeColor(for: e.level).opacity(0.15))
//                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Text(e.message)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    .id(e.id)
                }
                .onChange(of: store.entries.last?.id) { _, last in
                    if autoScroll, let last { withAnimation { proxy.scrollTo(last, anchor: .bottom) } }
                }
            }

            /*
             HStack {
                 Picker("Level", selection: $selectedLevel) {
                     Text("All").tag(LogLevel?.none)
                     Text("Error").tag(LogLevel?.some(.error))
                     Text("Warning").tag(LogLevel?.some(.warning))
                     Text("Info").tag(LogLevel?.some(.info))
                     Text("Debug").tag(LogLevel?.some(.debug))
                     Text("Test").tag(LogLevel?.some(.test))
                 }
                 .pickerStyle(.segmented)

                  //Disabling Buttons for now
                                 Spacer()

                                 Button("Copy") {
                                     let text = store.entries.filter(passes).map {
                                         "[\($0.level)] \($0.message)"
                                     }.joined(separator: "\n")
                                     #if os(macOS)
                                     NSPasteboard.general.clearContents()
                                     NSPasteboard.general.setString(text, forType: .string)
                                     #endif
                                 }

                                 Button("Export") {
                                     //exportLog(store.entries.filter(passes))
                                 }

                                 Button("Clear") {
                                     // optional: expose a clear API on Logger/LogStore if you want
                                 }

             }
             .padding(.horizontal, 8)
             */
        }
        .padding(10)
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: d)
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
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
        case .debug: return .gray
        case .test: return .green
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
