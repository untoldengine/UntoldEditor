//
//  EditorRenderingSystemTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import MetalKit
import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class EditorRenderingSystemTests: XCTestCase {
    private var originalRenderEnvironment: Bool!
    private var originalVisualDebug: Bool!
    private var originalGameMode: Bool!
    private var originalFXAAEnabled: Bool!

    override func setUp() {
        super.setUp()

        // Save original state
        originalRenderEnvironment = renderEnvironment
        originalVisualDebug = visualDebug
        originalGameMode = gameMode
        originalFXAAEnabled = FXAAParams.shared.enabled

        // Set up Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Metal device is not available.")
            return
        }

        renderInfo.device = device
        renderInfo.commandQueue = device.makeCommandQueue()
        vertexDescriptor.model = MDLVertexDescriptor()

        // Reset to default test state
        renderEnvironment = false
        visualDebug = false
        gameMode = false
        FXAAParams.shared.enabled = false
    }

    override func tearDown() {
        // Restore original state
        renderEnvironment = originalRenderEnvironment
        visualDebug = originalVisualDebug
        gameMode = originalGameMode
        FXAAParams.shared.enabled = originalFXAAEnabled

        super.tearDown()
    }

    // MARK: - buildEditModeGraph Tests

    func test_buildEditModeGraph_withGridMode_createsCorrectGraphStructure() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, finalPassID) = buildEditModeGraph()

        // Assert - Verify grid mode structure
        XCTAssertNotNil(graph["grid"], "Grid mode should create grid pass")
        XCTAssertNil(graph["environment"], "Grid mode should not create environment pass")

        // Verify essential passes exist
        XCTAssertNotNil(graph["shadow"], "Shadow pass should exist")
        XCTAssertNotNil(graph["batchedShadow"], "Batched shadow pass should exist")
        XCTAssertNotNil(graph["model"], "Model pass should exist")
        XCTAssertNotNil(graph["batchedModel"], "Batched model pass should exist")
        XCTAssertNotNil(graph["lightPass"], "Light pass should exist")
        XCTAssertNotNil(graph["outline"], "Highlight/outline pass should exist")
        XCTAssertNotNil(graph["lightVisualPass"], "Light visual pass should exist")
        XCTAssertNotNil(graph["gizmo"], "Gizmo pass should exist")
        XCTAssertNotNil(graph["precomp"], "Pre-composite pass should exist")
        XCTAssertNotNil(graph["look"], "Look pass should exist")
        XCTAssertNotNil(graph["outputTransform"], "Output transform pass should exist")

        // Verify final pass ID
        XCTAssertEqual(finalPassID, "outputTransform", "Final pass ID should be outputTransform")
    }

    func test_buildEditModeGraph_withEnvironmentMode_createsCorrectGraphStructure() {
        // Arrange
        renderEnvironment = true

        // Act
        let (graph, finalPassID) = buildEditModeGraph()

        // Assert - Verify environment mode structure
        XCTAssertNotNil(graph["environment"], "Environment mode should create environment pass")
        XCTAssertNil(graph["grid"], "Environment mode should not create grid pass")

        // Verify essential passes exist
        XCTAssertNotNil(graph["shadow"], "Shadow pass should exist")
        XCTAssertNotNil(graph["batchedShadow"], "Batched shadow pass should exist")
        XCTAssertNotNil(graph["model"], "Model pass should exist")
        XCTAssertNotNil(graph["batchedModel"], "Batched model pass should exist")
        XCTAssertNotNil(graph["lightPass"], "Light pass should exist")
        XCTAssertNotNil(graph["outline"], "Highlight/outline pass should exist")
        XCTAssertNotNil(graph["lightVisualPass"], "Light visual pass should exist")
        XCTAssertNotNil(graph["gizmo"], "Gizmo pass should exist")
        XCTAssertNotNil(graph["precomp"], "Pre-composite pass should exist")
        XCTAssertNotNil(graph["look"], "Look pass should exist")
        XCTAssertNotNil(graph["outputTransform"], "Output transform pass should exist")

        // Verify final pass ID
        XCTAssertEqual(finalPassID, "outputTransform", "Final pass ID should be outputTransform")
    }

    func test_buildEditModeGraph_gridMode_hasCorrectDependencies() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify dependency chain
        XCTAssertEqual(graph["grid"]?.dependencies.count, 0, "Grid pass should have no dependencies")
        XCTAssertEqual(graph["shadow"]?.dependencies, ["grid"], "Shadow should depend on grid")
        XCTAssertEqual(graph["batchedShadow"]?.dependencies, ["shadow"], "Batched shadow should depend on shadow")
        XCTAssertEqual(graph["model"]?.dependencies, ["batchedShadow"], "Model should depend on batchedShadow")
        XCTAssertEqual(graph["batchedModel"]?.dependencies, ["model"], "Batched model should depend on model")
        XCTAssertTrue(graph["lightPass"]?.dependencies.contains("model") ?? false, "Light pass should depend on model")
        XCTAssertTrue(graph["lightPass"]?.dependencies.contains("shadow") ?? false, "Light pass should depend on shadow")
        XCTAssertTrue(graph["lightPass"]?.dependencies.contains("batchedModel") ?? false, "Light pass should depend on batchedModel")
        XCTAssertEqual(graph["outline"]?.dependencies, ["batchedModel"], "Outline should depend on batchedModel")
        XCTAssertEqual(graph["lightVisualPass"]?.dependencies, ["outline"], "Light visual pass should depend on outline")
        XCTAssertEqual(graph["gizmo"]?.dependencies, ["lightVisualPass"], "Gizmo should depend on light visual pass")
        XCTAssertEqual(graph["transparency"]?.dependencies, ["lightPass"], "Transparency should depend on light pass")

        let precompDeps = graph["precomp"]?.dependencies ?? []
        XCTAssertTrue(precompDeps.contains("model"), "Precomp should depend on model")
        XCTAssertTrue(precompDeps.contains("gizmo"), "Precomp should depend on gizmo")
        XCTAssertTrue(precompDeps.contains("transparency"), "Precomp should depend on transparency")

        XCTAssertEqual(graph["look"]?.dependencies, ["precomp"], "Look should depend on precomp")
        XCTAssertEqual(graph["outputTransform"]?.dependencies, ["look"], "Output transform should depend on look")
    }

    func test_buildEditModeGraph_environmentMode_hasCorrectDependencies() {
        // Arrange
        renderEnvironment = true

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify dependency chain
        XCTAssertEqual(graph["environment"]?.dependencies.count, 0, "Environment pass should have no dependencies")
        XCTAssertEqual(graph["shadow"]?.dependencies, ["environment"], "Shadow should depend on environment")
        XCTAssertEqual(graph["batchedShadow"]?.dependencies, ["shadow"], "Batched shadow should depend on shadow")
        XCTAssertEqual(graph["model"]?.dependencies, ["batchedShadow"], "Model should depend on batchedShadow")
        XCTAssertEqual(graph["batchedModel"]?.dependencies, ["model"], "Batched model should depend on model")
    }

    func test_buildEditModeGraph_canBeTopologicallySorted() throws {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify graph can be sorted without cycles
        XCTAssertNoThrow(try topologicalSortGraph(graph: graph), "Edit mode graph should be sortable without cycles")

        let sortedPasses = try topologicalSortGraph(graph: graph)
        XCTAssertTrue(sortedPasses.count > 0, "Sorted passes should not be empty")
        XCTAssertEqual(sortedPasses.count, graph.count, "Sorted passes count should match graph size")
    }

    func test_buildEditModeGraph_topologicalOrder_respectsDependencies() throws {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()
        let sortedPasses = try topologicalSortGraph(graph: graph)
        let order = sortedPasses.map(\.id)

        // Assert - Verify topological constraints
        assertTopologicalConstraints(order: order, constraints: [
            ("grid", "shadow"),
            ("shadow", "model"),
            ("model", "lightPass"),
            ("model", "outline"),
            ("outline", "lightVisualPass"),
            ("lightVisualPass", "gizmo"),
            ("gizmo", "precomp"),
            ("lightPass", "precomp"),
            ("precomp", "look"),
            ("look", "outputTransform"),
        ])
    }

    func test_buildEditModeGraph_switchingBetweenModes_producesCorrectBasePass() {
        // Test grid mode
        renderEnvironment = false
        var (graph, _) = buildEditModeGraph()
        XCTAssertNotNil(graph["grid"], "Grid mode should have grid pass")
        XCTAssertNil(graph["environment"], "Grid mode should not have environment pass")

        // Switch to environment mode
        renderEnvironment = true
        (graph, _) = buildEditModeGraph()
        XCTAssertNotNil(graph["environment"], "Environment mode should have environment pass")
        XCTAssertNil(graph["grid"], "Environment mode should not have grid pass")

        // Switch back to grid mode
        renderEnvironment = false
        (graph, _) = buildEditModeGraph()
        XCTAssertNotNil(graph["grid"], "Grid mode should have grid pass after switching back")
        XCTAssertNil(graph["environment"], "Grid mode should not have environment pass after switching back")
    }

    func test_buildEditModeGraph_allPassesHaveExecutionFunctions() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify all passes have execution functions
        for (passID, pass) in graph {
            XCTAssertNotNil(pass.execute, "Pass '\(passID)' should have an execution function")
        }
    }

    func test_buildEditModeGraph_passIDsMatchKeys() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify pass IDs match dictionary keys
        for (key, pass) in graph {
            XCTAssertEqual(key, pass.id, "Dictionary key '\(key)' should match pass ID '\(pass.id)'")
        }
    }

    func test_buildEditModeGraph_allDependenciesExist() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert - Verify all dependencies exist in the graph
        for (passID, pass) in graph {
            for dependency in pass.dependencies {
                XCTAssertNotNil(graph[dependency],
                                "Pass '\(passID)' depends on '\(dependency)', but '\(dependency)' doesn't exist in graph")
            }
        }
    }

    // MARK: - Graph Structure Validation Tests

    func test_buildEditModeGraph_noCyclicDependencies() {
        // Test both modes for cycles
        for useEnvironment in [true, false] {
            renderEnvironment = useEnvironment
            let (graph, _) = buildEditModeGraph()

            XCTAssertNoThrow(
                try topologicalSortGraph(graph: graph),
                "Graph should not contain cycles in \(useEnvironment ? "environment" : "grid") mode"
            )
        }
    }

    func test_buildEditModeGraph_precompPass_hasMultipleDependencies() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert
        guard let precompPass = graph["precomp"] else {
            XCTFail("Precomp pass should exist")
            return
        }

        XCTAssertEqual(precompPass.dependencies.count, 4, "Precomp should have exactly 4 dependencies")
        XCTAssertTrue(precompPass.dependencies.contains("model"), "Precomp should depend on model")
        XCTAssertTrue(precompPass.dependencies.contains("gizmo"), "Precomp should depend on gizmo")
        XCTAssertTrue(precompPass.dependencies.contains("transparency"), "Precomp should depend on transparency")
        XCTAssertTrue(precompPass.dependencies.contains("gaussian"), "Precomp should depend on gaussian")
    }

    func test_buildEditModeGraph_lightPass_dependsOnModelAndShadow() {
        // Arrange
        renderEnvironment = false

        // Act
        let (graph, _) = buildEditModeGraph()

        // Assert
        guard let lightPass = graph["lightPass"] else {
            XCTFail("Light pass should exist")
            return
        }

        XCTAssertEqual(lightPass.dependencies.count, 3, "Light pass should have exactly 3 dependencies")
        XCTAssertTrue(lightPass.dependencies.contains("model"), "Light pass should depend on model")
        XCTAssertTrue(lightPass.dependencies.contains("shadow"), "Light pass should depend on shadow")
        XCTAssertTrue(lightPass.dependencies.contains("batchedModel"), "Light pass should depend on batchedModel")
    }

    // MARK: - Helper Methods

    private func assertTopologicalConstraints(
        order: [String],
        constraints: [(String, String)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        for (before, after) in constraints {
            guard let beforeIndex = order.firstIndex(of: before),
                  let afterIndex = order.firstIndex(of: after)
            else {
                XCTFail("Both '\(before)' and '\(after)' should be in the sorted order", file: file, line: line)
                continue
            }

            XCTAssertLessThan(
                beforeIndex,
                afterIndex,
                "'\(before)' should come before '\(after)' in topological order",
                file: file,
                line: line
            )
        }
    }
}
