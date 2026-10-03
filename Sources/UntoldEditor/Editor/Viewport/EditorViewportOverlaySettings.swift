//
//  EditorViewportOverlaySettings.swift
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

/// Which overlays the viewport shows, and the form of the frame statistics.
/// All of them show at first; the choices persist across launches.
final class EditorViewportOverlaySettings: ObservableObject {
    static let shared = EditorViewportOverlaySettings(defaults: .standard)

    static let keyPrefix = "editor.viewport.overlay."
    static let statsKey = "editor.viewport.stats"

    /// The overlays that were hidden from the View menu.
    @Published private(set) var hidden: Set<ViewportOverlay>

    private let defaults: UserDefaults?

    /// `defaults` nil keeps nothing, for tests.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        hidden = Set(ViewportOverlay.allCases.filter { overlay in
            defaults?.object(forKey: Self.keyPrefix + overlay.rawValue) as? Bool == false
        })
    }

    func isShown(_ overlay: ViewportOverlay) -> Bool {
        hidden.contains(overlay) == false
    }

    func setShown(_ overlay: ViewportOverlay, _ shown: Bool) {
        if shown {
            hidden.remove(overlay)
        } else {
            hidden.insert(overlay)
        }
        defaults?.set(shown, forKey: Self.keyPrefix + overlay.rawValue)
    }

    func toggle(_ overlay: ViewportOverlay) {
        setShown(overlay, isShown(overlay) == false)
    }

    // MARK: - The frame statistics

    /// The form of the statistics the editor starts with: the last one chosen
    /// in the View menu, or the compact form when none was.
    var storedStatsMode: EngineStatsOverlayMode {
        defaults?.string(forKey: Self.statsKey).flatMap(EngineStatsOverlayMode.init(rawValue:)) ?? .simplified
    }

    func storeStatsMode(_ mode: EngineStatsOverlayMode) {
        defaults?.set(mode.rawValue, forKey: Self.statsKey)
    }
}
