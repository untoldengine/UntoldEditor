//
//  EditorControllerTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Combine
import Foundation
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class EditorControllerTests: XCTestCase {
    private var controller: EditorController!
    private var selectionManager: SelectionManager!
    private var tempBaseURL: URL!
    private var originalBasePath: URL?

    override func setUp() {
        super.setUp()

        // Create temporary directory
        let tempDir = FileManager.default.temporaryDirectory
        tempBaseURL = tempDir.appendingPathComponent("EditorControllerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempBaseURL, withIntermediateDirectories: true)

        // Save original base path
        originalBasePath = EditorAssetBasePath.shared.basePath

        // Create fresh scene
        scene = Scene()

        // Initialize controller
        selectionManager = SelectionManager()
        controller = EditorController(selectionManager: selectionManager)
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempBaseURL)

        // Restore original base path
        EditorAssetBasePath.shared.basePath = originalBasePath

        super.tearDown()
    }

    // MARK: - EditorController Initialization Tests

    func test_editorController_initializes() {
        // Assert
        XCTAssertNotNil(controller, "Controller should initialize")
        XCTAssertNotNil(controller.selectionManager, "Should have selection manager")
        XCTAssertTrue(controller.isEnabled, "Should be enabled by default")
    }

    func test_editorController_hasInitialState() {
        // Assert
        XCTAssertEqual(controller.activeMode, .none, "Active mode should be none initially")
        XCTAssertEqual(controller.activeAxis, .none, "Active axis should be none initially")
        XCTAssertNil(controller.currentSceneURL, "Current scene URL should be nil initially")
    }

    // MARK: - Active Mode Tests

    func test_editorController_activeMode_isPublished() {
        // Arrange
        var receivedModes: [TransformManipulationMode] = []
        let cancellable = controller.$activeMode.sink { mode in
            receivedModes.append(mode)
        }

        // Act
        controller.activeMode = .translate
        controller.activeMode = .rotate

        // Assert
        XCTAssertEqual(receivedModes.count, 3, "Should receive initial + 2 updates")
        XCTAssertEqual(receivedModes[0], .none, "Initial mode should be none")
        XCTAssertEqual(receivedModes[1], .translate, "First update should be translate")
        XCTAssertEqual(receivedModes[2], .rotate, "Second update should be rotate")

        cancellable.cancel()
    }

    func test_editorController_activeAxis_isPublished() {
        // Arrange
        var receivedAxes: [TransformAxis] = []
        let cancellable = controller.$activeAxis.sink { axis in
            receivedAxes.append(axis)
        }

        // Act
        controller.activeAxis = .x
        controller.activeAxis = .y

        // Assert
        XCTAssertEqual(receivedAxes.count, 3, "Should receive initial + 2 updates")
        XCTAssertEqual(receivedAxes[1], .x, "First update should be x")
        XCTAssertEqual(receivedAxes[2], .y, "Second update should be y")

        cancellable.cancel()
    }

    func test_editorController_resetActiveAxis() {
        // Arrange
        controller.activeAxis = .x

        // Act
        controller.resetActiveAxis()

        // Assert
        XCTAssertEqual(controller.activeAxis, .none, "Active axis should be reset to none")
    }

    // MARK: - SelectionDelegate Tests

    func test_editorController_implementsSelectionDelegate() {
        // Assert
        XCTAssertNotNil(controller as? SelectionDelegate, "Should implement SelectionDelegate protocol")
    }

    func test_editorController_didSelectEntity_updatesSelectionManager() {
        // Arrange
        let entity = createEntity()

        // Act
        controller.didSelectEntity(entity)

        // Wait for main queue dispatch
        let expectation = expectation(description: "Selection update")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertEqual(selectionManager.selectedEntity, entity, "Selection manager should be updated")
    }

    func test_editorController_refreshInspector_triggersPublisher() {
        // Arrange
        var updateCount = 0
        let cancellable = selectionManager.objectWillChange.sink { _ in
            updateCount += 1
        }

        // Act
        controller.refreshInspector()

        // Wait for main queue dispatch
        let expectation = expectation(description: "Refresh update")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        // Assert
        XCTAssertGreaterThan(updateCount, 0, "Should trigger selection manager update")

        cancellable.cancel()
    }

    // MARK: - EditorAssetBasePath Tests

    func test_editorAssetBasePath_initializes() {
        // Arrange
        let basePath = EditorAssetBasePath.shared

        // Assert
        XCTAssertNotNil(basePath, "EditorAssetBasePath should initialize")
    }

    func test_editorAssetBasePath_canSetBasePath() {
        // Act
        EditorAssetBasePath.shared.basePath = tempBaseURL

        // Assert
        XCTAssertEqual(EditorAssetBasePath.shared.basePath, tempBaseURL, "Base path should be set")
    }

    func test_editorAssetBasePath_canClearBasePath() {
        // Arrange
        EditorAssetBasePath.shared.basePath = tempBaseURL

        // Act
        EditorAssetBasePath.shared.basePath = nil

        // Assert
        XCTAssertNil(EditorAssetBasePath.shared.basePath, "Base path should be cleared")
    }

    func test_editorAssetBasePath_syncsWithEngineGlobal() {
        // Act
        EditorAssetBasePath.shared.basePath = tempBaseURL

        // Assert
        XCTAssertEqual(assetBasePath, tempBaseURL, "Engine global should sync with EditorAssetBasePath")
    }

    func test_editorAssetBasePath_projectName_extractsCorrectly() {
        // Arrange: Create path structure: ProjectRoot/Sources/ProjectName/GameData
        let projectRoot = tempBaseURL.appendingPathComponent("MyGame", isDirectory: true)
        let sources = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        let projectName = sources.appendingPathComponent("MyGame", isDirectory: true)
        let gameData = projectName.appendingPathComponent("GameData", isDirectory: true)

        try? FileManager.default.createDirectory(at: gameData, withIntermediateDirectories: true)

        // Act
        EditorAssetBasePath.shared.basePath = gameData

        // Assert
        XCTAssertEqual(EditorAssetBasePath.shared.projectName, "MyGame", "Should extract project name correctly")
    }

    func test_editorAssetBasePath_projectName_returnsNilWhenNoBasePath() {
        // Arrange
        EditorAssetBasePath.shared.basePath = nil

        // Act
        let projectName = EditorAssetBasePath.shared.projectName

        // Assert
        XCTAssertNil(projectName, "Should return nil when no base path")
    }

    func test_editorAssetBasePath_isPublished() {
        // Arrange
        var receivedPaths: [URL?] = []
        let cancellable = EditorAssetBasePath.shared.$basePath.sink { path in
            receivedPaths.append(path)
        }

        // Act
        EditorAssetBasePath.shared.basePath = tempBaseURL

        // Assert
        XCTAssertEqual(receivedPaths.count, 2, "Should receive initial + 1 update")
        XCTAssertEqual(receivedPaths[1], tempBaseURL, "Should receive updated path")

        cancellable.cancel()
    }

    // MARK: - Scene Save/Load Helper Tests

    func test_saveSceneDirect_createsFile() throws {
        // Arrange
        let sceneData = SceneData(entities: [])
        let saveURL = tempBaseURL.appendingPathComponent("test_scene.untoldscene")

        // Act
        saveSceneDirect(sceneData: sceneData, to: saveURL)

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path), "Scene file should be created")

        // Verify content
        let data = try Data(contentsOf: saveURL)
        let decoded = try JSONDecoder().decode(SceneData.self, from: data)
        XCTAssertEqual(decoded.entities.count, 0, "Should match saved scene data")
    }

    func test_saveSceneDirect_createsJSON() throws {
        // Arrange
        let sceneData = SceneData(entities: [])
        let saveURL = tempBaseURL.appendingPathComponent("test_scene.untoldscene")

        // Act
        saveSceneDirect(sceneData: sceneData, to: saveURL)

        // Assert
        let content = try String(contentsOf: saveURL)
        XCTAssertTrue(content.contains("{"), "Should be valid JSON")
        XCTAssertTrue(content.contains("\"entities\""), "Should contain entities key")
    }

    func test_saveSceneDirect_copiesIntoScenesFolder() throws {
        // Arrange
        EditorAssetBasePath.shared.basePath = tempBaseURL

        let scenesFolder = tempBaseURL.appendingPathComponent("Scenes", isDirectory: true)
        try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        let saveURL = tempBaseURL.appendingPathComponent("test_scene.untoldscene")
        let sceneData = SceneData(entities: [])

        // Act
        saveSceneDirect(sceneData: sceneData, to: saveURL)

        // Assert
        let copiedURL = scenesFolder.appendingPathComponent("test_scene.untoldscene")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedURL.path), "Scene should be copied to Scenes folder")
    }

    func test_saveSceneDirect_doesNotDuplicateWhenAlreadyInScenesFolder() throws {
        // Arrange
        EditorAssetBasePath.shared.basePath = tempBaseURL

        let scenesFolder = tempBaseURL.appendingPathComponent("Scenes", isDirectory: true)
        try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        let saveURL = scenesFolder.appendingPathComponent("test_scene.untoldscene")
        let sceneData = SceneData(entities: [])

        // Act
        saveSceneDirect(sceneData: sceneData, to: saveURL)

        // Assert
        let files = try FileManager.default.contentsOfDirectory(at: scenesFolder, includingPropertiesForKeys: nil)
        let sceneFiles = files.filter { $0.lastPathComponent == "test_scene.untoldscene" }
        XCTAssertEqual(sceneFiles.count, 1, "Should not create duplicate when already in Scenes folder")
    }

    func test_saveSceneDirect_overwritesExistingFile() throws {
        // Arrange
        EditorAssetBasePath.shared.basePath = tempBaseURL

        let scenesFolder = tempBaseURL.appendingPathComponent("Scenes", isDirectory: true)
        try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        let saveURL = scenesFolder.appendingPathComponent("test_scene.untoldscene")

        // Create initial file
        let initialData = SceneData(entities: [])
        saveSceneDirect(sceneData: initialData, to: saveURL)

        // Act: Overwrite with different data
        let newData = SceneData(entities: [])
        saveSceneDirect(sceneData: newData, to: saveURL)

        // Assert
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path), "File should still exist")

        let files = try FileManager.default.contentsOfDirectory(at: scenesFolder, includingPropertiesForKeys: nil)
        let sceneFiles = files.filter { $0.lastPathComponent == "test_scene.untoldscene" }
        XCTAssertEqual(sceneFiles.count, 1, "Should have exactly one file")
    }

    func test_loadGameScene_decodesCorrectly() throws {
        // Arrange: Create a scene file manually
        let sceneData = SceneData(entities: [])
        let saveURL = tempBaseURL.appendingPathComponent("test_load.untoldscene")

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(sceneData)
        try jsonData.write(to: saveURL)

        // Act: Load the scene (note: loadGameScene() uses NSOpenPanel, so we can't test it directly)
        // Instead, we test that the saved file can be decoded
        let loadedData = try Data(contentsOf: saveURL)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SceneData.self, from: loadedData)

        // Assert
        XCTAssertEqual(decoded.entities.count, 0, "Should decode correctly")
    }

    // MARK: - EditorComponentsState Tests

    func test_editorComponentsState_initializes() {
        // Arrange
        let state = EditorComponentsState.shared

        // Assert
        XCTAssertNotNil(state, "EditorComponentsState should initialize")
        XCTAssertTrue(state.components.isEmpty, "Components should be empty initially")
    }

    func test_editorComponentsState_canAddComponent() {
        // Arrange
        let state = EditorComponentsState.shared
        let entity = createEntity()
        let componentKey = ObjectIdentifier(RenderComponent.self)

        // Act
        state.components[entity] = [componentKey: ComponentOption_Editor(
            id: 1,
            name: "Render Component",
            type: RenderComponent.self,
            view: { _, _, _ in AnyView(EmptyView()) }
        )]

        // Assert
        XCTAssertEqual(state.components.count, 1, "Should have one entity")
        XCTAssertNotNil(state.components[entity]?[componentKey], "Should have component for entity")
    }

    func test_editorComponentsState_canClear() {
        // Arrange
        let state = EditorComponentsState.shared
        let entity = createEntity()
        let componentKey = ObjectIdentifier(RenderComponent.self)

        state.components[entity] = [componentKey: ComponentOption_Editor(
            id: 1,
            name: "Render Component",
            type: RenderComponent.self,
            view: { _, _, _ in AnyView(EmptyView()) }
        )]

        // Act
        state.clear()

        // Assert
        XCTAssertTrue(state.components.isEmpty, "Components should be cleared")
    }

    func test_editorComponentsState_isPublished() {
        // Arrange
        let state = EditorComponentsState.shared
        var updateCount = 0
        let cancellable = state.objectWillChange.sink { _ in
            updateCount += 1
        }

        let entity = createEntity()
        let componentKey = ObjectIdentifier(RenderComponent.self)

        // Act
        state.components[entity] = [componentKey: ComponentOption_Editor(
            id: 1,
            name: "Render Component",
            type: RenderComponent.self,
            view: { _, _, _ in AnyView(EmptyView()) }
        )]

        // Assert
        XCTAssertGreaterThan(updateCount, 0, "Should publish updates")

        cancellable.cancel()
    }

    // MARK: - Notification Tests

    func test_assetBrowserReloadNotification_exists() {
        // Assert
        XCTAssertNotNil(Notification.Name.assetBrowserReload, "assetBrowserReload notification should exist")
    }

    func test_assetBrowserReloadNotification_canPost() {
        // Arrange
        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .assetBrowserReload,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }

        // Act
        NotificationCenter.default.post(name: .assetBrowserReload, object: nil)

        // Wait briefly
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        // Assert
        XCTAssertTrue(notificationReceived, "Should receive notification")

        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Integration Tests

    func test_editorController_fullWorkflow() {
        // 1. Initialize with selection manager
        XCTAssertNotNil(controller.selectionManager, "Should have selection manager")

        // 2. Select entity
        let entity = createEntity()
        controller.didSelectEntity(entity)

        let expectation = expectation(description: "Selection update")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(selectionManager.selectedEntity, entity, "Entity should be selected")

        // 3. Set manipulation mode
        controller.activeMode = .translate
        XCTAssertEqual(controller.activeMode, .translate, "Mode should be set")

        // 4. Set active axis
        controller.activeAxis = .x
        XCTAssertEqual(controller.activeAxis, .x, "Axis should be set")

        // 5. Reset axis
        controller.resetActiveAxis()
        XCTAssertEqual(controller.activeAxis, .none, "Axis should be reset")
    }

    func test_editorAssetBasePath_fullWorkflow() {
        // 1. Set base path
        EditorAssetBasePath.shared.basePath = tempBaseURL
        XCTAssertEqual(EditorAssetBasePath.shared.basePath, tempBaseURL, "Base path should be set")

        // 2. Verify engine global sync
        XCTAssertEqual(assetBasePath, tempBaseURL, "Engine global should sync")

        // 3. Create project structure
        let projectRoot = tempBaseURL.appendingPathComponent("TestProject", isDirectory: true)
        let sources = projectRoot.appendingPathComponent("Sources", isDirectory: true)
        let projectName = sources.appendingPathComponent("TestProject", isDirectory: true)
        let gameData = projectName.appendingPathComponent("GameData", isDirectory: true)

        try? FileManager.default.createDirectory(at: gameData, withIntermediateDirectories: true)

        EditorAssetBasePath.shared.basePath = gameData

        // 4. Extract project name
        XCTAssertEqual(EditorAssetBasePath.shared.projectName, "TestProject", "Should extract project name")

        // 5. Clear base path
        EditorAssetBasePath.shared.basePath = nil
        XCTAssertNil(EditorAssetBasePath.shared.basePath, "Base path should be cleared")
    }

    func test_saveAndLoadSceneWorkflow() throws {
        // 1. Set up base path
        EditorAssetBasePath.shared.basePath = tempBaseURL

        let scenesFolder = tempBaseURL.appendingPathComponent("Scenes", isDirectory: true)
        try FileManager.default.createDirectory(at: scenesFolder, withIntermediateDirectories: true)

        // 2. Create and save scene
        let sceneData = SceneData(entities: [])
        let saveURL = scenesFolder.appendingPathComponent("workflow_test.untoldscene")

        saveSceneDirect(sceneData: sceneData, to: saveURL)

        // 3. Verify file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: saveURL.path), "Scene file should exist")

        // 4. Load and verify
        let loadedData = try Data(contentsOf: saveURL)
        let decoded = try JSONDecoder().decode(SceneData.self, from: loadedData)

        XCTAssertEqual(decoded.entities.count, 0, "Loaded scene should match saved scene")
    }
}
