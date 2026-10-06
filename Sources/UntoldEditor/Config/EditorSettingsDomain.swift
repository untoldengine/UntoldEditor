//
//  EditorSettingsDomain.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Where the editor's settings live. An executable run from the build folder
/// (`swift run`, Xcode) had no bundle, so `UserDefaults` kept them under its
/// name, `UntoldEditor`. With the identity the executable carries now they
/// live under the app's identifier, as the packaged app's do: the first launch
/// with the identifier takes over what the old domain holds.
enum EditorSettingsDomain {
    /// The domain an executable without an identity gets: its name.
    static let legacyName = "UntoldEditor"

    /// Set in the current domain once the old one has been looked at.
    static let adoptedKey = "EditorSettingsDomain.adoptedLegacySettings"

    /// Copies every setting of the old domain that the current one lacks, once;
    /// a setting the current domain already has stays. Returns the keys copied.
    @discardableResult
    static func adoptLegacySettings(
        defaults: UserDefaults = .standard,
        current: String? = Bundle.main.bundleIdentifier,
        legacy: String = legacyName
    ) -> [String] {
        guard let current, current != legacy else {
            return []
        }
        var settings = defaults.persistentDomain(forName: current) ?? [:]
        guard settings[adoptedKey] == nil else {
            return []
        }
        settings[adoptedKey] = true
        var copied: [String] = []
        for (key, value) in defaults.persistentDomain(forName: legacy) ?? [:] where settings[key] == nil {
            settings[key] = value
            copied.append(key)
        }
        defaults.setPersistentDomain(settings, forName: current)
        return copied.sorted()
    }
}
