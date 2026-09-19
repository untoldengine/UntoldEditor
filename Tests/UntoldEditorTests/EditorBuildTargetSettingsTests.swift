//
//  EditorBuildTargetSettingsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
@testable import UntoldEditor
import XCTest

final class EditorBuildTargetSettingsTests: XCTestCase {
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "EditorBuildTargetSettingsTests.\(UUID().uuidString)"
        return try (XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }

    func test_defaultTargetIsMacOS() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(EditorBuildTargetSettings(defaults: defaults).target, .macOS)
    }

    func test_targetPersistsPerProject() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectA = URL(fileURLWithPath: "/tmp/ProjectA")
        let projectB = URL(fileURLWithPath: "/tmp/ProjectB")

        EditorBuildTargetSettings(defaults: defaults, projectRoot: projectA).target = .visionOS

        XCTAssertEqual(EditorBuildTargetSettings(defaults: defaults, projectRoot: projectA).target, .visionOS)
        XCTAssertEqual(EditorBuildTargetSettings(defaults: defaults, projectRoot: projectB).target, .macOS)
    }

    func test_followingTheOpenProjectSwitchesTheTarget() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let projectA = URL(fileURLWithPath: "/tmp/ProjectA")
        let projectB = URL(fileURLWithPath: "/tmp/ProjectB")
        EditorBuildTargetSettings(defaults: defaults, projectRoot: projectB).target = .iOS

        let settings = EditorBuildTargetSettings(defaults: defaults, projectRoot: projectA)
        let projects = PassthroughSubject<URL?, Never>()
        settings.follow(projects.eraseToAnyPublisher())

        let switched = expectation(description: "target reloaded for project B")
        let subscription = settings.$target.dropFirst().sink { target in
            XCTAssertEqual(target, .iOS)
            switched.fulfill()
        }
        projects.send(projectB)
        wait(for: [switched], timeout: 1)
        subscription.cancel()

        // Reloading does not write project B's target under project A's key.
        XCTAssertEqual(EditorBuildTargetSettings(defaults: defaults, projectRoot: projectA).target, .macOS)
    }

    func test_projectRootIsThreeLevelsAboveGameData() {
        let base = URL(fileURLWithPath: "/Users/me/Games/MyGame/Sources/MyGame/GameData")
        XCTAssertEqual(EditorBuildTargetSettings.projectRoot(of: base)?.path, "/Users/me/Games/MyGame")
        XCTAssertNil(EditorBuildTargetSettings.projectRoot(of: nil))
    }

    func test_statusLabelNamesTheBackend() {
        XCTAssertEqual(EditorBuildTarget.macOS.statusLabel, "macOS · Metal")
        XCTAssertEqual(EditorBuildTarget.allCases.map(\.title), ["macOS", "iOS", "visionOS"])
    }
}
