//
//  ScriptProjectManagerTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class ScriptProjectManagerTests: XCTestCase {
    private var manager: ScriptProjectManager!
    private var tempBaseURL: URL!

    override func setUp() {
        super.setUp()

        manager = ScriptProjectManager.shared

        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempBaseURL = tempDir.appendingPathComponent("ScriptProjectManagerTests-\(UUID().uuidString)", isDirectory: true)

        try? FileManager.default.createDirectory(at: tempBaseURL, withIntermediateDirectories: true)

        // Set the asset base path to our temp directory
        EditorAssetBasePath.shared.basePath = tempBaseURL
    }

    override func tearDown() {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempBaseURL)

        // Clear asset base path
        EditorAssetBasePath.shared.basePath = nil

        super.tearDown()
    }

    // MARK: - Path Resolution Tests

    func test_scriptsDirectory_returnsNilWhenNoBasePath() {
        // Arrange
        EditorAssetBasePath.shared.basePath = nil

        // Act
        let scriptsDir = manager.scriptsDirectory()

        // Assert
        XCTAssertNil(scriptsDir, "Should return nil when no asset base path is set")
    }

    func test_scriptsDirectory_returnsCorrectPath() {
        // Act
        let scriptsDir = manager.scriptsDirectory()

        // Assert
        XCTAssertNotNil(scriptsDir, "Should return a path")
        XCTAssertEqual(scriptsDir?.lastPathComponent, "Scripts", "Should point to Scripts folder")
        XCTAssertTrue(scriptsDir?.path.contains(tempBaseURL.path) ?? false, "Should be under temp base path")
    }

    func test_sourcesDirectory_returnsCorrectPath() {
        // Act
        let sourcesDir = manager.sourcesDirectory()

        // Assert
        XCTAssertNotNil(sourcesDir, "Should return a path")
        XCTAssertTrue(sourcesDir?.path.contains("Sources/GenerateScripts") ?? false, "Should include Sources/GenerateScripts")
    }

    func test_generatedDirectory_returnsCorrectPath() {
        // Act
        let generatedDir = manager.generatedDirectory()

        // Assert
        XCTAssertNotNil(generatedDir, "Should return a path")
        XCTAssertTrue(generatedDir?.path.contains("Generated") ?? false, "Should include Generated")
    }

    // MARK: - Project Status Tests

    func test_isProjectInitialized_returnsFalseForEmptyDirectory() {
        // Act
        let isInitialized = manager.isProjectInitialized()

        // Assert
        XCTAssertFalse(isInitialized, "Should return false when no project files exist")
    }

    func test_isProjectInitialized_returnsTrueWhenFilesExist() throws {
        // Arrange: Initialize a project
        try manager.initializeProject()

        // Act
        let isInitialized = manager.isProjectInitialized()

        // Assert
        XCTAssertTrue(isInitialized, "Should return true after initialization")
    }

    // MARK: - Project Initialization Tests

    func test_initializeProject_createsPackageSwift() throws {
        // Act
        try manager.initializeProject()

        // Assert
        guard let scriptsDir = manager.scriptsDirectory() else {
            XCTFail("Scripts directory should exist")
            return
        }

        let packageSwift = scriptsDir.appendingPathComponent("Package.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageSwift.path), "Package.swift should be created")

        let content = try String(contentsOf: packageSwift)
        XCTAssertTrue(content.contains("swift-tools-version"), "Package.swift should contain swift-tools-version")
        XCTAssertTrue(content.contains("GameScripts"), "Package.swift should contain package name")
    }

    func test_initializeProject_createsGenerateScriptsSwift() throws {
        // Act
        try manager.initializeProject()

        // Assert
        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let generateScripts = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: generateScripts.path), "GenerateScripts.swift should be created")

        let content = try String(contentsOf: generateScripts)
        XCTAssertTrue(content.contains("@main"), "GenerateScripts.swift should contain @main")
        XCTAssertTrue(content.contains("struct GenerateScripts"), "Should contain GenerateScripts struct")
    }

    func test_initializeProject_createsGitignore() throws {
        // Act
        try manager.initializeProject()

        // Assert
        guard let scriptsDir = manager.scriptsDirectory() else {
            XCTFail("Scripts directory should exist")
            return
        }

        let gitignore = scriptsDir.appendingPathComponent(".gitignore")
        XCTAssertTrue(FileManager.default.fileExists(atPath: gitignore.path), ".gitignore should be created")

        let content = try String(contentsOf: gitignore)
        XCTAssertTrue(content.contains(".build/"), ".gitignore should contain .build/")
        XCTAssertTrue(content.contains("Generated/"), ".gitignore should contain Generated/")
    }

    func test_initializeProject_createsDirectoryStructure() throws {
        // Act
        try manager.initializeProject()

        // Assert
        guard let sourcesDir = manager.sourcesDirectory(),
              let generatedDir = manager.generatedDirectory()
        else {
            XCTFail("Directories should exist")
            return
        }

        var isSourcesDir: ObjCBool = false
        var isGeneratedDir: ObjCBool = false

        XCTAssertTrue(FileManager.default.fileExists(atPath: sourcesDir.path, isDirectory: &isSourcesDir), "Sources directory should exist")
        XCTAssertTrue(isSourcesDir.boolValue, "Sources should be a directory")

        XCTAssertTrue(FileManager.default.fileExists(atPath: generatedDir.path, isDirectory: &isGeneratedDir), "Generated directory should exist")
        XCTAssertTrue(isGeneratedDir.boolValue, "Generated should be a directory")
    }

    func test_initializeProject_throwsWhenNoBasePath() {
        // Arrange
        EditorAssetBasePath.shared.basePath = nil

        // Act & Assert
        XCTAssertThrowsError(try manager.initializeProject()) { error in
            guard let scriptError = error as? ScriptProjectError else {
                XCTFail("Should throw ScriptProjectError")
                return
            }
            XCTAssertEqual(scriptError, ScriptProjectError.noAssetBasePath, "Should throw noAssetBasePath error")
        }
    }

    func test_initializeProject_throwsWhenAlreadyInitialized() throws {
        // Arrange
        try manager.initializeProject()

        // Act & Assert
        XCTAssertThrowsError(try manager.initializeProject()) { error in
            guard let scriptError = error as? ScriptProjectError else {
                XCTFail("Should throw ScriptProjectError")
                return
            }
            XCTAssertEqual(scriptError, ScriptProjectError.projectAlreadyExists, "Should throw projectAlreadyExists error")
        }
    }

    // MARK: - Script Creation Tests

    func test_createNewScript_createsScriptFile() throws {
        // Arrange
        try manager.initializeProject()

        // Act
        try manager.createNewScript(name: "PlayerController")

        // Assert
        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let scriptPath = sourcesDir.appendingPathComponent("PlayerController.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: scriptPath.path), "Script file should be created")

        let content = try String(contentsOf: scriptPath)
        XCTAssertTrue(content.contains("PlayerController"), "Script should contain the script name")
        XCTAssertTrue(content.contains("extension GenerateScripts"), "Script should contain extension")
        XCTAssertTrue(content.contains("generatePlayerController"), "Script should contain generate function")
    }

    func test_createNewScript_addsInvocationToMain() throws {
        // Arrange
        try manager.initializeProject()

        // Act
        try manager.createNewScript(name: "EnemyAI")

        // Assert
        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let mainScript = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let content = try String(contentsOf: mainScript)

        XCTAssertTrue(content.contains("generateEnemyAI(to: outputDir)"), "Main script should contain invocation")
    }

    func test_createNewScript_throwsWhenNotInitialized() {
        // Act & Assert
        XCTAssertThrowsError(try manager.createNewScript(name: "Test")) { error in
            guard let scriptError = error as? ScriptProjectError else {
                XCTFail("Should throw ScriptProjectError")
                return
            }
            XCTAssertEqual(scriptError, ScriptProjectError.projectNotInitialized, "Should throw projectNotInitialized error")
        }
    }

    func test_createNewScript_throwsForEmptyName() throws {
        // Arrange
        try manager.initializeProject()

        // Act & Assert
        XCTAssertThrowsError(try manager.createNewScript(name: "")) { error in
            guard let scriptError = error as? ScriptProjectError else {
                XCTFail("Should throw ScriptProjectError")
                return
            }
            XCTAssertEqual(scriptError, ScriptProjectError.invalidScriptName, "Should throw invalidScriptName error")
        }
    }

    func test_createNewScript_throwsForInvalidName() throws {
        // Arrange
        try manager.initializeProject()

        let invalidNames = [
            "123Invalid", // Starts with number
            "Invalid Name", // Contains space
            "Invalid-Name", // Contains hyphen
            "Invalid.Name", // Contains dot
        ]

        // Act & Assert
        for name in invalidNames {
            XCTAssertThrowsError(try manager.createNewScript(name: name), "Should throw for invalid name: \(name)") { error in
                guard let scriptError = error as? ScriptProjectError else {
                    XCTFail("Should throw ScriptProjectError for \(name)")
                    return
                }
                XCTAssertEqual(scriptError, ScriptProjectError.invalidScriptName, "Should throw invalidScriptName for \(name)")
            }
        }
    }

    func test_createNewScript_acceptsValidNames() throws {
        // Arrange
        try manager.initializeProject()

        let validNames = [
            "PlayerController",
            "EnemyAI",
            "Item123",
            "WeaponSystem",
        ]

        // Act & Assert
        for name in validNames {
            XCTAssertNoThrow(try manager.createNewScript(name: name), "Should not throw for valid name: \(name)")

            guard let sourcesDir = manager.sourcesDirectory() else {
                XCTFail("Sources directory should exist")
                return
            }

            let scriptPath = sourcesDir.appendingPathComponent("\(name).swift")
            XCTAssertTrue(FileManager.default.fileExists(atPath: scriptPath.path), "Script should be created for \(name)")
        }
    }

    func test_createNewScript_doesNotDuplicateInvocation() throws {
        // Arrange
        try manager.initializeProject()
        try manager.createNewScript(name: "Player")

        // Act: Try to create again
        try manager.createNewScript(name: "Player")

        // Assert
        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let mainScript = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let content = try String(contentsOf: mainScript)

        let matches = content.components(separatedBy: "generatePlayer(to: outputDir)").count - 1
        XCTAssertEqual(matches, 1, "Invocation should only appear once")
    }

    // MARK: - List Scripts Tests

    func test_listScriptFiles_returnsEmptyForNewProject() throws {
        // Arrange
        try manager.initializeProject()

        // Act
        let scripts = manager.listScriptFiles()

        // Assert
        XCTAssertTrue(scripts.isEmpty, "Should return empty array for new project")
    }

    func test_listScriptFiles_returnsCreatedScripts() throws {
        // Arrange
        try manager.initializeProject()
        try manager.createNewScript(name: "Player")
        try manager.createNewScript(name: "Enemy")

        // Act
        let scripts = manager.listScriptFiles()

        // Assert
        XCTAssertEqual(scripts.count, 2, "Should return 2 scripts")

        let names = scripts.map(\.lastPathComponent)
        XCTAssertTrue(names.contains("Player.swift"), "Should contain Player.swift")
        XCTAssertTrue(names.contains("Enemy.swift"), "Should contain Enemy.swift")
    }

    func test_listScriptFiles_excludesGenerateScriptsSwift() throws {
        // Arrange
        try manager.initializeProject()
        try manager.createNewScript(name: "Test")

        // Act
        let scripts = manager.listScriptFiles()

        // Assert
        let names = scripts.map(\.lastPathComponent)
        XCTAssertFalse(names.contains("GenerateScripts.swift"), "Should exclude GenerateScripts.swift")
    }

    func test_listScriptFiles_returnsEmptyWhenNoBasePath() {
        // Arrange
        EditorAssetBasePath.shared.basePath = nil

        // Act
        let scripts = manager.listScriptFiles()

        // Assert
        XCTAssertTrue(scripts.isEmpty, "Should return empty when no base path")
    }

    // MARK: - Remove Script Invocation Tests

    func test_removeScriptInvocationFromMain_removesInvocation() throws {
        // Arrange
        try manager.initializeProject()
        try manager.createNewScript(name: "TestScript")

        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let mainScript = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let contentBefore = try String(contentsOf: mainScript)
        XCTAssertTrue(contentBefore.contains("generateTestScript(to: outputDir)"), "Invocation should exist before removal")

        // Act
        manager.removeScriptInvocationFromMain(name: "TestScript")

        // Assert
        let contentAfter = try String(contentsOf: mainScript)
        XCTAssertFalse(contentAfter.contains("generateTestScript(to: outputDir)"), "Invocation should be removed")
    }

    func test_removeScriptInvocationFromMain_doesNothingWhenScriptNotFound() throws {
        // Arrange
        try manager.initializeProject()

        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let mainScript = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let contentBefore = try String(contentsOf: mainScript)

        // Act
        manager.removeScriptInvocationFromMain(name: "NonExistent")

        // Assert
        let contentAfter = try String(contentsOf: mainScript)
        XCTAssertEqual(contentBefore, contentAfter, "Content should remain unchanged")
    }

    // MARK: - Template Content Tests

    func test_packageSwiftTemplate_containsRequiredContent() throws {
        // Arrange
        try manager.initializeProject()

        guard let scriptsDir = manager.scriptsDirectory() else {
            XCTFail("Scripts directory should exist")
            return
        }

        // Act
        let packageSwift = scriptsDir.appendingPathComponent("Package.swift")
        let content = try String(contentsOf: packageSwift)

        // Assert
        XCTAssertTrue(content.contains("swift-tools-version"), "Should contain swift-tools-version")
        XCTAssertTrue(content.contains("Package("), "Should contain Package declaration")
        XCTAssertTrue(content.contains("name: \"GameScripts\""), "Should contain package name")
        XCTAssertTrue(content.contains("platforms:"), "Should contain platforms")
        XCTAssertTrue(content.contains(".macOS"), "Should contain macOS platform")
        XCTAssertTrue(content.contains("dependencies:"), "Should contain dependencies")
        XCTAssertTrue(content.contains("UntoldEngine"), "Should depend on UntoldEngine")
        XCTAssertTrue(content.contains("targets:"), "Should contain targets")
        XCTAssertTrue(content.contains(".executableTarget"), "Should contain executable target")
    }

    func test_generateScriptsTemplate_containsRequiredContent() throws {
        // Arrange
        try manager.initializeProject()

        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        // Act
        let generateScripts = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let content = try String(contentsOf: generateScripts)

        // Assert
        XCTAssertTrue(content.contains("@main"), "Should contain @main attribute")
        XCTAssertTrue(content.contains("struct GenerateScripts"), "Should contain struct declaration")
        XCTAssertTrue(content.contains("static func main()"), "Should contain main function")
        XCTAssertTrue(content.contains("#filePath"), "Should use #filePath for output directory")
        XCTAssertTrue(content.contains("outputDir"), "Should define outputDir variable")
    }

    func test_scriptTemplate_containsRequiredContent() throws {
        // Arrange
        try manager.initializeProject()

        // Act
        try manager.createNewScript(name: "TestController")

        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let scriptFile = sourcesDir.appendingPathComponent("TestController.swift")
        let content = try String(contentsOf: scriptFile)

        // Assert
        XCTAssertTrue(content.contains("extension GenerateScripts"), "Should extend GenerateScripts")
        XCTAssertTrue(content.contains("static func generateTestController"), "Should contain generate function")
        XCTAssertTrue(content.contains("buildScript"), "Should use buildScript")
        XCTAssertTrue(content.contains("onUpdate()"), "Should contain onUpdate")
        XCTAssertTrue(content.contains("saveUSCScript"), "Should save USC script")
        XCTAssertTrue(content.contains("TestController.uscript"), "Should reference .uscript output file")
    }

    func test_gitignoreTemplate_containsRequiredContent() throws {
        // Arrange
        try manager.initializeProject()

        guard let scriptsDir = manager.scriptsDirectory() else {
            XCTFail("Scripts directory should exist")
            return
        }

        // Act
        let gitignore = scriptsDir.appendingPathComponent(".gitignore")
        let content = try String(contentsOf: gitignore)

        // Assert
        XCTAssertTrue(content.contains(".build/"), "Should ignore .build directory")
        XCTAssertTrue(content.contains("Generated/"), "Should ignore Generated directory")
        XCTAssertTrue(content.contains(".DS_Store"), "Should ignore .DS_Store")
    }

    // MARK: - Integration Tests

    func test_fullWorkflow_initializeCreateListRemove() throws {
        // 1. Initialize
        try manager.initializeProject()
        XCTAssertTrue(manager.isProjectInitialized(), "Project should be initialized")

        // 2. Create scripts
        try manager.createNewScript(name: "Player")
        try manager.createNewScript(name: "Enemy")
        try manager.createNewScript(name: "Weapon")

        // 3. List scripts
        let scripts = manager.listScriptFiles()
        XCTAssertEqual(scripts.count, 3, "Should have 3 scripts")

        // 4. Remove one script invocation
        manager.removeScriptInvocationFromMain(name: "Enemy")

        // Verify removal
        guard let sourcesDir = manager.sourcesDirectory() else {
            XCTFail("Sources directory should exist")
            return
        }

        let mainScript = sourcesDir.appendingPathComponent("GenerateScripts.swift")
        let content = try String(contentsOf: mainScript)

        XCTAssertTrue(content.contains("generatePlayer(to: outputDir)"), "Player invocation should remain")
        XCTAssertFalse(content.contains("generateEnemy(to: outputDir)"), "Enemy invocation should be removed")
        XCTAssertTrue(content.contains("generateWeapon(to: outputDir)"), "Weapon invocation should remain")
    }
}
