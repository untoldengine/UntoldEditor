//
//  GaussianRuntimeInspector.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import SwiftUI
import UntoldEngine

/// Read-only rows: what the file costs the engine on this Mac (`GaussianRuntimeSummary`, from
/// the file's index) and the live GPU and pool bytes, refreshed every second.
struct GaussianRuntimeInspector: View {
    let entityId: EntityID
    let sourceURL: URL
    @State private var summary: GaussianRuntimeSummary?
    @State private var note: String?
    @State private var liveLine: String?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runtime")
                .font(.caption)
                .foregroundColor(.editorTextSecondary)
            if let summary {
                ForEach(summary.inspectorRows, id: \.label) { row in
                    HStack(alignment: .top, spacing: 6) {
                        Text(row.label)
                            .foregroundColor(.editorTextSecondary)
                            .frame(width: 84, alignment: .leading)
                        Text(row.value)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                }
            } else if let note {
                Text(note)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let liveLine {
                Text(liveLine)
                    .font(.caption)
                    .foregroundColor(.editorTextSecondary)
            }
        }
        .task(id: sourceURL) {
            // A bounded index read, off the main thread.
            let url = sourceURL
            let read = await Task.detached { () -> (GaussianRuntimeSummary?, String?) in
                guard url.pathExtension.lowercased() == "untoldgs" else {
                    return (nil, gaussianPlacementDetail(for: url))
                }
                return ((try? GaussianRuntimeSummary.read(url: url)), nil)
            }.value
            summary = read.0
            note = read.1 ?? (read.0 == nil ? "Could not read \(url.lastPathComponent)" : nil)
            liveLine = gaussianRuntimeLiveLine(entityId: entityId)
        }
        .onReceive(ticker) { _ in
            liveLine = gaussianRuntimeLiveLine(entityId: entityId)
        }
    }
}
