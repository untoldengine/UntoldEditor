//
//  EngineStatsView.swift
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

enum EngineStatsOverlayMode {
    case off
    case simplified
    case advanced
}

final class EditorEngineStatsStore: ObservableObject {
    static let shared = EditorEngineStatsStore()

    @Published private(set) var snapshot: EngineStatsSnapshot = .init()
    @Published var overlayMode: EngineStatsOverlayMode = .off
    @Published var loggingEnabled: Bool
    @Published var loggingProfile: EngineStatsLoggingProfile
    @Published var loggingIntervalSeconds: Double

    private var pollCancellable: AnyCancellable?

    private init() {
        loggingEnabled = EngineStatsMonitor.shared.enableLogging
        loggingProfile = EngineStatsMonitor.shared.loggingProfile
        loggingIntervalSeconds = EngineStatsMonitor.shared.loggingIntervalSeconds

        snapshot = getEngineStatsSnapshot()

        pollCancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.snapshot = getEngineStatsSnapshot()
            }
    }

    func setLoggingEnabled(_ enabled: Bool) {
        loggingEnabled = enabled
        setEngineStatsLogging(
            enabled: loggingEnabled,
            profile: loggingProfile,
            intervalSeconds: loggingIntervalSeconds
        )
    }

    func setLoggingProfile(_ profile: EngineStatsLoggingProfile) {
        loggingProfile = profile
        setEngineStatsLogging(
            enabled: loggingEnabled,
            profile: loggingProfile,
            intervalSeconds: loggingIntervalSeconds
        )
    }

    func setLoggingInterval(_ seconds: Double) {
        loggingIntervalSeconds = max(0.1, seconds)
        setEngineStatsLogging(
            enabled: loggingEnabled,
            profile: loggingProfile,
            intervalSeconds: loggingIntervalSeconds
        )
    }

    func setOverlaySimplifiedEnabled(_ enabled: Bool) {
        if enabled {
            overlayMode = .simplified
        } else if overlayMode == .simplified {
            overlayMode = .off
        }
    }

    func setOverlayAdvancedEnabled(_ enabled: Bool) {
        if enabled {
            overlayMode = .advanced
        } else if overlayMode == .advanced {
            overlayMode = .off
        }
    }
}

struct EngineStatsOverlayView: View {
    @ObservedObject private var store = EditorEngineStatsStore.shared

    var body: some View {
        Group {
            switch store.overlayMode {
            case .off:
                EmptyView()
            case .simplified:
                simplifiedOverlay(store.snapshot)
            case .advanced:
                advancedOverlay(store.snapshot)
            }
        }
    }

    private func simplifiedOverlay(_ snapshot: EngineStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Engine Stats")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.editorTextPrimary)

            Text(compactOverlayLine(snapshot))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.editorScrim)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: Color.editorShadow, radius: 8, x: 0, y: 2)
        .allowsHitTesting(false)
        .padding(12)
    }

    private func advancedOverlay(_ snapshot: EngineStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Engine Stats (Advanced)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.editorTextPrimary)

            Text(formatEngineStatsOverlay(snapshot))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.editorTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.editorScrim)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
        .cornerRadius(8)
        .shadow(color: Color.editorShadow, radius: 8, x: 0, y: 2)
        .allowsHitTesting(false)
        .padding(12)
    }

    private func compactOverlayLine(_ snapshot: EngineStatsSnapshot) -> String {
        "F\(snapshot.frameIndex) " +
            "fps \(formatFPS(snapshot.timing.frameTotalMs)) " +
            "frame \(formatMs(snapshot.timing.frameTotalMs))ms " +
            "upd \(formatMs(snapshot.timing.updateMs)) " +
            "rnd \(formatMs(snapshot.timing.renderTotalMs)) " +
            "cul \(formatMs(snapshot.timing.cullingMs)) " +
            "| draws \(snapshot.render.drawCallsTotal) " +
            "tris \(snapshot.render.trianglesTotal) " +
            "vis \(snapshot.render.visibleInstances)"
    }

    private func formatMs(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatFPS(_ frameMs: Double) -> String {
        guard frameMs > 0 else { return "0.0" }
        return String(format: "%.1f", 1000.0 / frameMs)
    }
}
