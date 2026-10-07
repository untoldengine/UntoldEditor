//
//  EditorSettingsDomainTests.swift
//  UntoldEditorTests
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

@testable import UntoldEditor
import XCTest

final class EditorSettingsDomainTests: XCTestCase {
    private let legacy = "untold.test.settings.legacy.\(UUID().uuidString)"
    private let current = "untold.test.settings.current.\(UUID().uuidString)"
    private let defaults = UserDefaults.standard

    override func tearDown() {
        defaults.removePersistentDomain(forName: legacy)
        defaults.removePersistentDomain(forName: current)
        super.tearDown()
    }

    func test_takesOverWhatTheOldDomainHas_andKeepsWhatTheCurrentOneHas() {
        defaults.setPersistentDomain(["layout": "old", "snap": true], forName: legacy)
        defaults.setPersistentDomain(["layout": "new"], forName: current)

        let copied = EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: current, legacy: legacy)

        XCTAssertEqual(copied, ["snap"])
        let settings = defaults.persistentDomain(forName: current)
        XCTAssertEqual(settings?["layout"] as? String, "new")
        XCTAssertEqual(settings?["snap"] as? Bool, true)
        XCTAssertEqual(defaults.persistentDomain(forName: legacy)?["layout"] as? String, "old", "the old domain is left as it is")
    }

    func test_onlyOnce_aLaterChangeOfTheOldDomainIsNotCopied() {
        defaults.setPersistentDomain(["snap": true], forName: legacy)
        EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: current, legacy: legacy)
        defaults.setPersistentDomain(["snap": true, "later": 1], forName: legacy)

        let copied = EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: current, legacy: legacy)

        XCTAssertEqual(copied, [])
        XCTAssertNil(defaults.persistentDomain(forName: current)?["later"])
    }

    func test_anEmptyOldDomain_isLookedAtOnceToo() {
        let copied = EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: current, legacy: legacy)

        XCTAssertEqual(copied, [])
        XCTAssertEqual(defaults.persistentDomain(forName: current)?[EditorSettingsDomain.adoptedKey] as? Bool, true)
    }

    func test_withoutAnIdentity_orWithTheOldDomainAsTheCurrentOne_nothingIsWritten() {
        defaults.setPersistentDomain(["snap": true], forName: legacy)

        XCTAssertEqual(EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: nil, legacy: legacy), [])
        XCTAssertEqual(EditorSettingsDomain.adoptLegacySettings(defaults: defaults, current: legacy, legacy: legacy), [])

        XCTAssertNil(defaults.persistentDomain(forName: current))
        XCTAssertNil(defaults.persistentDomain(forName: legacy)?[EditorSettingsDomain.adoptedKey])
    }
}
