//
//  GaussianTwinPreviewSettings.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldGaussianTwins

/// The View > Preview Splat Twins toggle: whether `GaussianTwinSystem` (package
/// UntoldGaussianTwins) runs in the editor viewport, swapping linked meshes for their splat
/// twins as the scene camera approaches, exactly as an app running the system would. Shared
/// between the AppKit menu (checkmark) and SwiftUI; persisted in `UserDefaults`, on by default.
final class GaussianTwinPreviewSettings: ObservableObject {
    static let shared = GaussianTwinPreviewSettings(defaults: .standard)

    static let isEnabledDefaultsKey = "editor.gaussianTwins.preview"

    /// What turning the preview on and off does to the engine; the live editor installs and
    /// uninstalls `GaussianTwinSystem.shared`, tests inject counters.
    struct Installer {
        var install: () -> Void
        var uninstall: () -> Void
        /// Forgets which scene links the system already adopted, so links in a freshly loaded
        /// scene (entity ids are reused) are picked up again.
        var resetAdoption: () -> Void

        static let live = Installer(
            install: { GaussianTwinSystem.shared.install() },
            uninstall: { GaussianTwinSystem.shared.uninstall() },
            resetAdoption: { GaussianTwinSystem.shared.resetSceneLinkAdoption() }
        )
    }

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.isEnabledDefaultsKey)
            guard isActivated else { return }
            applyToEngine()
        }
    }

    /// Set once the editor has an engine to install into (`activate()`); before that the
    /// toggle only records the preference.
    private(set) var isActivated = false
    private let defaults: UserDefaults
    private let installer: Installer

    init(defaults: UserDefaults, installer: Installer = .live) {
        self.defaults = defaults
        self.installer = installer
        if defaults.object(forKey: Self.isEnabledDefaultsKey) == nil {
            isEnabled = true
        } else {
            isEnabled = defaults.bool(forKey: Self.isEnabledDefaultsKey)
        }
    }

    /// Installs the system when the preference is on. Called once the renderer exists.
    func activate() {
        isActivated = true
        applyToEngine()
    }

    /// Called when the scene is loaded, cleared or the project switches: the old scene's
    /// entities are gone and their ids will be reused, so adoption starts over and an align
    /// mode on the old entities ends.
    func sceneDidReset() {
        GaussianTwinAlignMode.shared.leave()
        installer.resetAdoption()
    }

    private func applyToEngine() {
        if isEnabled {
            // Links the system examined while it was off (or before a reload) are adopted
            // again; `uninstall()` keeps its examined set.
            installer.resetAdoption()
            installer.install()
        } else {
            // Nothing swaps without the system: an align mode would only leave the shells off.
            GaussianTwinAlignMode.shared.leave()
            installer.uninstall()
        }
    }
}
