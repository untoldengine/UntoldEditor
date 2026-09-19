//
//  EditorEngineStatsStore.swift
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
