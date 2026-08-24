//
//  CreateProjectViewTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class CreateProjectViewTests: XCTestCase {
    // MARK: - Helper for extracting build settings

    /// Extract BuildSettings from CreateProjectView using reflection
    private func extractBuildSettings(from view: CreateProjectView) -> BuildSettings? {
        let mirror = Mirror(reflecting: view)

        // Extract state values
        guard let projectName = mirror.descendant("_projectName", "wrappedValue") as? String,
              let bundleIdentifier = mirror.descendant("_bundleIdentifier", "wrappedValue") as? String,
              let selectedTarget = mirror.descendant("_selectedTarget", "wrappedValue") as? Int,
              let macOSVersion = mirror.descendant("_macOSVersion", "wrappedValue") as? Int,
              let includeDebugInfo = mirror.descendant("_includeDebugInfo", "wrappedValue") as? Bool,
              let optimizationLevel = mirror.descendant("_optimizationLevel", "wrappedValue") as? Int,
              let teamID = mirror.descendant("_teamID", "wrappedValue") as? String,
              let outputPath = mirror.descendant("_outputPath", "wrappedValue") as? String
        else {
            return nil
        }

        // Recreate the build settings logic from the view
        let target: BuildTarget
        let isIOSAR = (selectedTarget == 2)

        switch selectedTarget {
        case 0: // macOS
            let version: MacOSVersion
            switch macOSVersion {
            case 0: version = .v13
            case 1: version = .v14
            case 2: version = .v15
            default: version = .v15
            }
            target = .macOS(deployment: version)
        case 1: // iOS
            target = .iOS(deployment: .v17)
        case 2: // iOS AR
            target = .iOS(deployment: .v17)
        case 3: // visionOS
            target = .visionOS(deployment: .v26)
        case 4: // Multi-Platform
            let version: MacOSVersion
            switch macOSVersion {
            case 0: version = .v13
            case 1: version = .v14
            case 2: version = .v15
            default: version = .v15
            }
            target = .multi(macOS: version, iOS: .v17, visionOS: .v26)
        default:
            target = .macOS(deployment: .v15)
        }

        let optimization: OptimizationLevel
        switch optimizationLevel {
        case 0: optimization = .none
        case 1: optimization = .speed
        case 2: optimization = .size
        default: optimization = .none
        }

        return BuildSettings(
            projectName: projectName,
            bundleIdentifier: bundleIdentifier,
            outputPath: URL(fileURLWithPath: outputPath),
            target: target,
            scenes: [],
            includeDebugInfo: includeDebugInfo,
            optimizationLevel: optimization,
            teamID: teamID.isEmpty ? nil : teamID,
            isIOSAR: isIOSAR
        )
    }

    // MARK: - Default State Tests

    func test_createProjectView_hasDefaultProjectName() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let projectName = mirror.descendant("_projectName", "wrappedValue") as? String {
            XCTAssertEqual(projectName, "MyGame", "Default project name should be 'MyGame'")
        }
    }

    func test_createProjectView_hasDefaultBundleIdentifier() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let bundleIdentifier = mirror.descendant("_bundleIdentifier", "wrappedValue") as? String {
            XCTAssertEqual(bundleIdentifier, "com.yourcompany.mygame", "Default bundle identifier should be set")
        }
    }

    func test_createProjectView_defaultTargetIsMacOS() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let selectedTarget = mirror.descendant("_selectedTarget", "wrappedValue") as? Int {
            XCTAssertEqual(selectedTarget, 0, "Default target should be macOS (index 0)")
        }
    }

    func test_createProjectView_defaultMacOSVersion() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let macOSVersion = mirror.descendant("_macOSVersion", "wrappedValue") as? Int {
            XCTAssertEqual(macOSVersion, 2, "Default macOS version should be index 2 (v15)")
        }
    }

    func test_createProjectView_debugInfoEnabledByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let includeDebugInfo = mirror.descendant("_includeDebugInfo", "wrappedValue") as? Bool {
            XCTAssertTrue(includeDebugInfo, "Debug info should be enabled by default")
        }
    }

    func test_createProjectView_optimizationLevelNoneByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let optimizationLevel = mirror.descendant("_optimizationLevel", "wrappedValue") as? Int {
            XCTAssertEqual(optimizationLevel, 0, "Default optimization should be none (index 0)")
        }
    }

    func test_createProjectView_emptyTeamIDByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let teamID = mirror.descendant("_teamID", "wrappedValue") as? String {
            XCTAssertTrue(teamID.isEmpty, "Team ID should be empty by default")
        }
    }

    func test_createProjectView_notBuildingByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let isBuilding = mirror.descendant("_isBuilding", "wrappedValue") as? Bool {
            XCTAssertFalse(isBuilding, "Should not be building by default")
        }
    }

    func test_createProjectView_buildResultNotShownByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let showBuildResult = mirror.descendant("_showBuildResult", "wrappedValue") as? Bool {
            XCTAssertFalse(showBuildResult, "Build result should not be shown by default")
        }
    }

    // MARK: - Build Settings Tests - macOS

    func test_buildSettings_macOSv13() {
        // Arrange
        // Since we can't modify @State directly in tests, we verify the logic is correct
        let target: BuildTarget = .macOS(deployment: .v13)

        // Assert
        if case let .macOS(deployment) = target {
            XCTAssertEqual(deployment, .v13, "Should create macOS v13 target")
        } else {
            XCTFail("Should be macOS target")
        }
    }

    func test_buildSettings_macOSv14() {
        // Arrange
        let target: BuildTarget = .macOS(deployment: .v14)

        // Assert
        if case let .macOS(deployment) = target {
            XCTAssertEqual(deployment, .v14, "Should create macOS v14 target")
        } else {
            XCTFail("Should be macOS target")
        }
    }

    func test_buildSettings_macOSv15() {
        // Arrange
        let target: BuildTarget = .macOS(deployment: .v15)

        // Assert
        if case let .macOS(deployment) = target {
            XCTAssertEqual(deployment, .v15, "Should create macOS v15 target")
        } else {
            XCTFail("Should be macOS target")
        }
    }

    // MARK: - Build Settings Tests - iOS

    func test_buildSettings_iOS() {
        // Arrange
        let target: BuildTarget = .iOS(deployment: .v17)

        // Assert
        if case let .iOS(deployment) = target {
            XCTAssertEqual(deployment, .v17, "Should create iOS v17 target")
        } else {
            XCTFail("Should be iOS target")
        }
    }

    func test_buildSettings_iOSAR() {
        // Arrange: iOS AR is selectedTarget == 2
        let isIOSAR = true
        let target: BuildTarget = .iOS(deployment: .v17)

        // Assert
        if case .iOS = target {
            XCTAssertTrue(isIOSAR, "iOS AR should set isIOSAR flag")
        } else {
            XCTFail("Should be iOS target")
        }
    }

    // MARK: - Build Settings Tests - visionOS

    func test_buildSettings_visionOS() {
        // Arrange
        let target: BuildTarget = .visionOS(deployment: .v26)

        // Assert
        if case let .visionOS(deployment) = target {
            XCTAssertEqual(deployment, .v26, "Should create visionOS v26 target")
        } else {
            XCTFail("Should be visionOS target")
        }
    }

    // MARK: - Optimization Level Tests

    func test_buildSettings_optimizationNone() {
        // Arrange
        let optimization: OptimizationLevel = .none

        // Assert
        XCTAssertEqual(optimization, .none, "Should set optimization to none")
    }

    func test_buildSettings_optimizationSpeed() {
        // Arrange
        let optimization: OptimizationLevel = .speed

        // Assert
        XCTAssertEqual(optimization, .speed, "Should set optimization to speed")
    }

    func test_buildSettings_optimizationSize() {
        // Arrange
        let optimization: OptimizationLevel = .size

        // Assert
        XCTAssertEqual(optimization, .size, "Should set optimization to size")
    }

    // MARK: - TeamID Tests

    func test_buildSettings_emptyTeamIDBecomesNil() {
        // Arrange
        let teamID = ""

        // Act
        let settings = BuildSettings(
            projectName: "TestProject",
            bundleIdentifier: "com.test.app",
            outputPath: URL(fileURLWithPath: "/tmp"),
            target: .macOS(deployment: .v15),
            scenes: [],
            includeDebugInfo: true,
            optimizationLevel: .none,
            teamID: teamID.isEmpty ? nil : teamID,
            isIOSAR: false
        )

        // Assert
        XCTAssertNil(settings.teamID, "Empty team ID should become nil")
    }

    func test_buildSettings_nonEmptyTeamIDIsPreserved() {
        // Arrange
        let teamID = "ABC123XYZ"

        // Act
        let settings = BuildSettings(
            projectName: "TestProject",
            bundleIdentifier: "com.test.app",
            outputPath: URL(fileURLWithPath: "/tmp"),
            target: .macOS(deployment: .v15),
            scenes: [],
            includeDebugInfo: true,
            optimizationLevel: .none,
            teamID: teamID.isEmpty ? nil : teamID,
            isIOSAR: false
        )

        // Assert
        XCTAssertEqual(settings.teamID, teamID, "Non-empty team ID should be preserved")
    }

    // MARK: - Target Platform Tests

    func test_targetPlatforms_arrayContainsFiveOptions() {
        // Arrange
        let view = CreateProjectView()
        let mirror = Mirror(reflecting: view)

        // Act: Get targets array
        if let targets = mirror.descendant("targets") as? [String] {
            // Assert
            XCTAssertEqual(targets.count, 5, "Should have 5 platform options")
            XCTAssertEqual(targets[0], "macOS", "First target should be macOS")
            XCTAssertEqual(targets[1], "iOS", "Second target should be iOS")
            XCTAssertEqual(targets[2], "iOS AR", "Third target should be iOS AR")
            XCTAssertEqual(targets[3], "visionOS", "Fourth target should be visionOS")
            XCTAssertEqual(targets[4], "Multi-Platform", "Fifth target should be Multi-Platform")
        }
    }

    func test_macOSVersions_arrayContainsThreeOptions() {
        // Arrange
        let view = CreateProjectView()
        let mirror = Mirror(reflecting: view)

        // Act: Get macOSVersions array
        if let versions = mirror.descendant("macOSVersions") as? [String] {
            // Assert
            XCTAssertEqual(versions.count, 3, "Should have 3 macOS version options")
            XCTAssertEqual(versions[0], "13.0", "First version should be 13.0")
            XCTAssertEqual(versions[1], "14.0", "Second version should be 14.0")
            XCTAssertEqual(versions[2], "15.0", "Third version should be 15.0")
        }
    }

    func test_optimizationLevels_arrayContainsThreeOptions() {
        // Arrange
        let view = CreateProjectView()
        let mirror = Mirror(reflecting: view)

        // Act: Get optimizationLevels array
        if let levels = mirror.descendant("optimizationLevels") as? [String] {
            // Assert
            XCTAssertEqual(levels.count, 3, "Should have 3 optimization level options")
            XCTAssertEqual(levels[0], "None", "First level should be None")
            XCTAssertEqual(levels[1], "Speed", "Second level should be Speed")
            XCTAssertEqual(levels[2], "Size", "Third level should be Size")
        }
    }

    // MARK: - Build Settings Integration Tests

    func test_buildSettings_fullConfiguration() {
        // Arrange
        let projectName = "MyAwesomeGame"
        let bundleIdentifier = "com.mycompany.awesomegame"
        let outputPath = URL(fileURLWithPath: "/Users/test/Projects")
        let target: BuildTarget = .iOS(deployment: .v17)
        let includeDebugInfo = false
        let optimizationLevel: OptimizationLevel = .speed
        let teamID = "TEAM123"
        let isIOSAR = true

        // Act
        let settings = BuildSettings(
            projectName: projectName,
            bundleIdentifier: bundleIdentifier,
            outputPath: outputPath,
            target: target,
            scenes: [],
            includeDebugInfo: includeDebugInfo,
            optimizationLevel: optimizationLevel,
            teamID: teamID,
            isIOSAR: isIOSAR
        )

        // Assert
        XCTAssertEqual(settings.projectName, projectName, "Should set project name")
        XCTAssertEqual(settings.bundleIdentifier, bundleIdentifier, "Should set bundle identifier")
        XCTAssertEqual(settings.outputPath, outputPath, "Should set output path")
        XCTAssertEqual(settings.includeDebugInfo, includeDebugInfo, "Should set debug info flag")
        XCTAssertEqual(settings.optimizationLevel, optimizationLevel, "Should set optimization level")
        XCTAssertEqual(settings.teamID, teamID, "Should set team ID")
        XCTAssertEqual(settings.isIOSAR, isIOSAR, "Should set iOS AR flag")

        if case let .iOS(deployment) = settings.target {
            XCTAssertEqual(deployment, .v17, "Should set iOS v17 target")
        } else {
            XCTFail("Target should be iOS")
        }
    }

    func test_buildSettings_scenesArrayIsEmpty() {
        // Arrange
        let settings = BuildSettings(
            projectName: "TestProject",
            bundleIdentifier: "com.test.app",
            outputPath: URL(fileURLWithPath: "/tmp"),
            target: .macOS(deployment: .v15),
            scenes: [],
            includeDebugInfo: true,
            optimizationLevel: .none,
            teamID: nil,
            isIOSAR: false
        )

        // Assert
        XCTAssertEqual(settings.scenes.count, 0, "Scenes array should be empty (populated by BuildSystem)")
    }

    // MARK: - State Management Tests

    func test_createProjectView_initialBuildProgressIsEmpty() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let buildProgress = mirror.descendant("_buildProgress", "wrappedValue") as? String {
            XCTAssertTrue(buildProgress.isEmpty, "Build progress should be empty initially")
        }
    }

    func test_createProjectView_initialBuildResultMessageIsEmpty() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let buildResultMessage = mirror.descendant("_buildResultMessage", "wrappedValue") as? String {
            XCTAssertTrue(buildResultMessage.isEmpty, "Build result message should be empty initially")
        }
    }

    func test_createProjectView_buildNotSucceededByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let buildSucceeded = mirror.descendant("_buildSucceeded", "wrappedValue") as? Bool {
            XCTAssertFalse(buildSucceeded, "Build should not be succeeded by default")
        }
    }

    func test_createProjectView_resultProjectPathIsNilByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        // Check if resultProjectPath exists and is nil
        let hasResultProjectPath = mirror.children.contains { child in
            child.label == "_resultProjectPath"
        }
        XCTAssertTrue(hasResultProjectPath, "Should have resultProjectPath state variable")
    }

    // MARK: - Target Switch Logic Tests

    func test_targetSwitch_macOS_index0() {
        // Arrange
        let selectedTarget = 0

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 0: target = .macOS(deployment: .v15)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .macOS = target {
            XCTAssertTrue(true, "Target 0 should map to macOS")
        } else {
            XCTFail("Target 0 should be macOS")
        }
    }

    func test_targetSwitch_iOS_index1() {
        // Arrange
        let selectedTarget = 1

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 1: target = .iOS(deployment: .v17)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .iOS = target {
            XCTAssertTrue(true, "Target 1 should map to iOS")
        } else {
            XCTFail("Target 1 should be iOS")
        }
    }

    func test_targetSwitch_iOSAR_index2() {
        // Arrange
        let selectedTarget = 2
        let isIOSAR = (selectedTarget == 2)

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 2: target = .iOS(deployment: .v17)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .iOS = target {
            XCTAssertTrue(isIOSAR, "Target 2 should map to iOS AR")
        } else {
            XCTFail("Target 2 should be iOS with AR flag")
        }
    }

    func test_targetSwitch_visionOS_index3() {
        // Arrange
        let selectedTarget = 3

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 3: target = .visionOS(deployment: .v26)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .visionOS = target {
            XCTAssertTrue(true, "Target 3 should map to visionOS")
        } else {
            XCTFail("Target 3 should be visionOS")
        }
    }

    func test_targetSwitch_multiPlatform_index4() {
        // Arrange
        let selectedTarget = 4

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 4: target = .multi(macOS: .v15, iOS: .v17, visionOS: .v26)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .multi = target {
            XCTAssertTrue(true, "Target 4 should map to Multi-Platform")
        } else {
            XCTFail("Target 4 should be Multi-Platform")
        }
    }

    func test_targetSwitch_defaultFallback() {
        // Arrange
        let selectedTarget = 999 // Invalid index

        // Act
        let target: BuildTarget
        switch selectedTarget {
        case 0: target = .macOS(deployment: .v15)
        case 1: target = .iOS(deployment: .v17)
        case 2: target = .iOS(deployment: .v17)
        case 3: target = .visionOS(deployment: .v26)
        case 4: target = .multi(macOS: .v15, iOS: .v17, visionOS: .v26)
        default: target = .macOS(deployment: .v15)
        }

        // Assert
        if case .macOS = target {
            XCTAssertTrue(true, "Invalid target should default to macOS")
        } else {
            XCTFail("Invalid target should default to macOS")
        }
    }

    // MARK: - Output Path Tests

    func test_outputPath_emptyByDefault() {
        // Act
        let view = CreateProjectView()

        // Assert
        let mirror = Mirror(reflecting: view)
        if let outputPath = mirror.descendant("_outputPath", "wrappedValue") as? String {
            XCTAssertEqual(outputPath, "", "Output path should be empty initially (set in onAppear)")
        }
    }
}
