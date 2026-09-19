//
//  LogExport.swift
//  UntoldEditor
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
