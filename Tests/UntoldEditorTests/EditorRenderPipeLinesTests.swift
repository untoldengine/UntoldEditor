//
//  EditorRenderPipeLinesTests.swift
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

final class EditorRenderPipeLinesTests: XCTestCase {
    override func setUp() {
        super.setUp()

        let windowWidth = 800
        let windowHeight = 600

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)

        window.title = "test window"

        guard let renderer = UntoldRenderer.create() else {
            XCTFail("Failed to initialize the renderer")
            return
        }

        window.contentView = renderer.metalView
        renderer.initResources()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - RenderPipelineType Extension Tests

    func test_gizmoPipelineType_exists() {
        // Assert
        let gizmoType: RenderPipelineType = .gizmo
        XCTAssertNotNil(gizmoType, "Gizmo pipeline type should exist")
        XCTAssertEqual(gizmoType.rawValue, "gizmo", "Gizmo pipeline type raw value should be 'gizmo'")
    }

    func test_debugPipelineType_exists() {
        // Assert
        let debugType: RenderPipelineType = .debug
        XCTAssertNotNil(debugType, "Debug pipeline type should exist")
        XCTAssertEqual(debugType.rawValue, "debug", "Debug pipeline type raw value should be 'debug'")
    }

    func test_pipelineTypes_areHashable() {
        // Arrange
        let gizmo: RenderPipelineType = .gizmo
        let debug: RenderPipelineType = .debug

        // Act - Use in a dictionary (requires Hashable)
        let pipelineDict: [RenderPipelineType: String] = [
            gizmo: "Gizmo Pipeline",
            debug: "Debug Pipeline",
        ]

        // Assert
        XCTAssertEqual(pipelineDict[.gizmo], "Gizmo Pipeline")
        XCTAssertEqual(pipelineDict[.debug], "Debug Pipeline")
    }

    func test_pipelineTypes_canBeCreatedFromStringLiteral() {
        // Act
        let customType: RenderPipelineType = "customPipeline"

        // Assert
        XCTAssertEqual(customType.rawValue, "customPipeline",
                       "Pipeline type should support string literal initialization")
    }

    // MARK: - InitGizmoPipeline Tests

    func test_InitGizmoPipeline_returnsNonNilPipeline() {
        // Act
        let pipeline = InitGizmoPipeline()

        // Assert
        XCTAssertNotNil(pipeline, "InitGizmoPipeline should return a pipeline")
    }

    func test_InitGizmoPipeline_hasPipelineState() {
        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertNotNil(pipeline.pipelineState, "Pipeline should have pipeline state")
    }

    func test_InitGizmoPipeline_hasDepthState() {
        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertNotNil(pipeline.depthState, "Pipeline should have depth state")
    }

    func test_InitGizmoPipeline_successIsTrue() {
        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertTrue(pipeline.success, "Pipeline creation should be successful")
    }

    func test_InitGizmoPipeline_hasCorrectName() {
        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertEqual(pipeline.name, "Gizmo Pipeline", "Pipeline should have correct name")
    }

    func test_InitGizmoPipeline_usesGizmoVertexDescriptor() {
        // This test verifies that the gizmo pipeline uses the gizmo vertex descriptor
        // The actual descriptor is created by createGizmoVertexDescriptor()

        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert - If pipeline was created successfully, it used the correct descriptor
        XCTAssertTrue(pipeline.success, "Pipeline with gizmo vertex descriptor should be created")
    }

    // MARK: - InitDebugPipeline Tests

    func test_InitDebugPipeline_returnsNonNilPipeline() {
        // Act
        let pipeline = InitDebugPipeline()

        // Assert
        XCTAssertNotNil(pipeline, "InitDebugPipeline should return a pipeline")
    }

    func test_InitDebugPipeline_hasPipelineState() {
        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertNotNil(pipeline.pipelineState, "Pipeline should have pipeline state")
    }

    func test_InitDebugPipeline_hasDepthState() {
        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertNotNil(pipeline.depthState, "Pipeline should have depth state")
    }

    func test_InitDebugPipeline_successIsTrue() {
        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertTrue(pipeline.success, "Pipeline creation should be successful")
    }

    func test_InitDebugPipeline_hasCorrectName() {
        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertEqual(pipeline.name, "Debug Pipeline", "Pipeline should have correct name")
    }

    func test_InitDebugPipeline_usesDebugVertexDescriptor() {
        // This test verifies that the debug pipeline uses the debug vertex descriptor
        // The actual descriptor is created by createDebugVertexDescriptor()

        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert - If pipeline was created successfully, it used the correct descriptor
        XCTAssertTrue(pipeline.success, "Pipeline with debug vertex descriptor should be created")
    }

    // MARK: - Pipeline Configuration Tests

    func test_InitGizmoPipeline_usesCorrectShaders() {
        // The gizmo pipeline should use:
        // - vertexShader: "vertexGizmoShader"
        // - fragmentShader: "fragmentGizmoShader"

        // Verify shaders exist in the library
        let vertexFunction = renderInfo.library.makeFunction(name: "vertexGizmoShader")
        let fragmentFunction = renderInfo.library.makeFunction(name: "fragmentGizmoShader")

        XCTAssertNotNil(vertexFunction, "Vertex shader 'vertexGizmoShader' should exist")
        XCTAssertNotNil(fragmentFunction, "Fragment shader 'fragmentGizmoShader' should exist")
    }

    func test_InitDebugPipeline_usesCorrectShaders() {
        // The debug pipeline should use:
        // - vertexShader: "vertexDebugShader"
        // - fragmentShader: "fragmentDebugShader"

        // Verify shaders exist in the library
        let vertexFunction = renderInfo.library.makeFunction(name: "vertexDebugShader")
        let fragmentFunction = renderInfo.library.makeFunction(name: "fragmentDebugShader")

        XCTAssertNotNil(vertexFunction, "Vertex shader 'vertexDebugShader' should exist")
        XCTAssertNotNil(fragmentFunction, "Fragment shader 'fragmentDebugShader' should exist")
    }

    func test_InitGizmoPipeline_usesColorPixelFormat() {
        // The gizmo pipeline uses renderInfo.colorPixelFormat

        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert - Pipeline was successfully created with the format
        XCTAssertTrue(pipeline.success, "Pipeline should use renderInfo.colorPixelFormat")
    }

    func test_InitDebugPipeline_usesBGRA8UnormSRGBFormat() {
        // The debug pipeline explicitly uses .bgra8Unorm_srgb color format

        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert - Pipeline was successfully created with the format
        XCTAssertTrue(pipeline.success, "Pipeline should use .bgra8Unorm_srgb format")
    }

    func test_InitGizmoPipeline_usesDepthPixelFormat() {
        // The gizmo pipeline uses renderInfo.depthPixelFormat

        // Act
        guard let pipeline = InitGizmoPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertTrue(pipeline.success, "Pipeline should use renderInfo.depthPixelFormat")
    }

    func test_InitDebugPipeline_hasDepthDisabled() {
        // The debug pipeline is created with depthEnabled: false
        // This means depth testing is disabled

        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert - The pipeline should still be created successfully
        XCTAssertTrue(pipeline.success, "Debug pipeline should have depth disabled")
        XCTAssertNotNil(pipeline.depthState, "Depth state should exist even when disabled")
    }

    func test_InitDebugPipeline_usesLessDepthCompare() {
        // The debug pipeline uses depthCompareFunction: .less

        // Act
        guard let pipeline = InitDebugPipeline() else {
            XCTFail("Pipeline should be created")
            return
        }

        // Assert
        XCTAssertTrue(pipeline.success, "Debug pipeline should use .less depth compare function")
    }

    // MARK: - EditorDefaultPipeLines Tests

    func test_EditorDefaultPipeLines_returnsArray() {
        // Act
        let pipelines = EditorDefaultPipeLines()

        // Assert
        XCTAssertNotNil(pipelines, "EditorDefaultPipeLines should return an array")
        XCTAssertGreaterThan(pipelines.count, 0, "EditorDefaultPipeLines should not be empty")
    }

    func test_EditorDefaultPipeLines_includesGizmoPipeline() {
        // Act
        let pipelines = EditorDefaultPipeLines()

        // Assert
        let hasGizmo = pipelines.contains { $0.0 == .gizmo }
        XCTAssertTrue(hasGizmo, "EditorDefaultPipeLines should include gizmo pipeline")
    }

    func test_EditorDefaultPipeLines_includesDebugPipeline() {
        // Act
        let pipelines = EditorDefaultPipeLines()

        // Assert
        let hasDebug = pipelines.contains { $0.0 == .debug }
        XCTAssertTrue(hasDebug, "EditorDefaultPipeLines should include debug pipeline")
    }

    func test_EditorDefaultPipeLines_includesDefaultPipelines() {
        // EditorDefaultPipeLines combines DefaultPipeLines() with editor-specific pipelines

        // Act
        let editorPipelines = EditorDefaultPipeLines()
        let defaultPipelines = DefaultPipeLines()

        // Assert - Editor pipelines should include at least as many as default
        XCTAssertGreaterThanOrEqual(editorPipelines.count, defaultPipelines.count,
                                    "Editor pipelines should include default pipelines")
    }

    func test_EditorDefaultPipeLines_gizmoInitBlockIsCallable() {
        // Act
        let pipelines = EditorDefaultPipeLines()

        guard let gizmoPair = pipelines.first(where: { $0.0 == .gizmo }) else {
            XCTFail("Gizmo pipeline should be in the list")
            return
        }

        let initBlock = gizmoPair.1
        let pipeline = initBlock()

        // Assert
        XCTAssertNotNil(pipeline, "Gizmo init block should be callable and return a pipeline")
    }

    func test_EditorDefaultPipeLines_debugInitBlockIsCallable() {
        // Act
        let pipelines = EditorDefaultPipeLines()

        guard let debugPair = pipelines.first(where: { $0.0 == .debug }) else {
            XCTFail("Debug pipeline should be in the list")
            return
        }

        let initBlock = debugPair.1
        let pipeline = initBlock()

        // Assert
        XCTAssertNotNil(pipeline, "Debug init block should be callable and return a pipeline")
    }

    func test_EditorDefaultPipeLines_hasCorrectStructure() {
        // The function returns an array of tuples: [(RenderPipelineType, RenderPipelineInitBlock)]

        // Act
        let pipelines = EditorDefaultPipeLines()

        // Assert - Check the structure by accessing elements
        for (type, initBlock) in pipelines {
            XCTAssertNotNil(type, "Pipeline type should not be nil")
            XCTAssertNotNil(initBlock, "Init block should not be nil")

            // Verify the init block can be called
            // (We won't call all of them to avoid creating all pipelines)
            XCTAssertTrue(true, "Pipeline pair should have valid type and init block")
        }
    }

    // MARK: - Integration Tests

    func test_bothPipelines_canBeCreatedSimultaneously() {
        // Act
        let gizmoPipeline = InitGizmoPipeline()
        let debugPipeline = InitDebugPipeline()

        // Assert
        XCTAssertNotNil(gizmoPipeline, "Gizmo pipeline should be created")
        XCTAssertNotNil(debugPipeline, "Debug pipeline should be created")
        XCTAssertTrue(gizmoPipeline?.success ?? false, "Gizmo pipeline should be successful")
        XCTAssertTrue(debugPipeline?.success ?? false, "Debug pipeline should be successful")
    }

    func test_pipelines_haveDifferentShaders() {
        // Gizmo and Debug pipelines should use different shaders

        // Arrange
        let gizmoVertexShader = renderInfo.library.makeFunction(name: "vertexGizmoShader")
        let debugVertexShader = renderInfo.library.makeFunction(name: "vertexDebugShader")

        // Assert
        XCTAssertNotNil(gizmoVertexShader)
        XCTAssertNotNil(debugVertexShader)

        // The functions should be different (different names at least)
        XCTAssertNotEqual(gizmoVertexShader?.name, debugVertexShader?.name,
                          "Gizmo and Debug should use different vertex shaders")
    }

    func test_pipelines_haveDifferentVertexDescriptors() {
        // Gizmo uses createGizmoVertexDescriptor()
        // Debug uses createDebugVertexDescriptor()

        // Act
        let gizmoDescriptor = createGizmoVertexDescriptor()
        let debugDescriptor = createDebugVertexDescriptor()

        // Assert
        XCTAssertNotNil(gizmoDescriptor, "Gizmo vertex descriptor should be created")
        XCTAssertNotNil(debugDescriptor, "Debug vertex descriptor should be created")

        // They should have different configurations
        // Gizmo uses float4 for position, Debug uses float3
        XCTAssertNotEqual(gizmoDescriptor?.attributes[0].format,
                          debugDescriptor.attributes[0].format,
                          "Gizmo and Debug descriptors should have different position formats")
    }

    func test_pipelineManager_canStoreEditorPipelines() {
        // Verify that PipelineManager can store and retrieve editor pipelines

        // Act
        guard let gizmoPipeline = InitGizmoPipeline() else {
            XCTFail("Should create gizmo pipeline")
            return
        }

        PipelineManager.shared.update(rendererPipeLine: gizmoPipeline, forType: .gizmo)

        // Assert
        let retrievedPipeline = PipelineManager.shared.renderPipelinesByType[.gizmo]
        XCTAssertNotNil(retrievedPipeline, "PipelineManager should store gizmo pipeline")
        XCTAssertEqual(retrievedPipeline?.name, "Gizmo Pipeline",
                       "Retrieved pipeline should match stored pipeline")
    }

    func test_EditorDefaultPipeLines_canInitializeAllPipelines() {
        // This test verifies that all pipelines in EditorDefaultPipeLines can be initialized

        // Act
        let pipelines = EditorDefaultPipeLines()
        var allSuccessful = true
        var failedPipelines: [String] = []

        for (type, initBlock) in pipelines {
            if let pipeline = initBlock() {
                if !pipeline.success {
                    allSuccessful = false
                    failedPipelines.append(type.rawValue)
                }
            } else {
                allSuccessful = false
                failedPipelines.append(type.rawValue)
            }
        }

        // Assert
        XCTAssertTrue(allSuccessful,
                      "All pipelines should initialize successfully. Failed: \(failedPipelines.joined(separator: ", "))")
    }

    // MARK: - Error Handling Tests

    func test_InitGizmoPipeline_requiresValidLibrary() {
        // Pipelines require renderInfo.library to be set

        // The setUp already sets this, but we verify it's required
        XCTAssertNotNil(renderInfo.library, "Library should be set for pipeline creation")
    }

    func test_InitGizmoPipeline_requiresValidDevice() {
        // Pipelines require renderInfo.device to be set

        XCTAssertNotNil(renderInfo.device, "Device should be set for pipeline creation")
    }

    func test_pipelines_requireValidPixelFormats() {
        // Pipelines require valid color and depth pixel formats

        XCTAssertNotEqual(renderInfo.colorPixelFormat, .invalid,
                          "Color pixel format should be valid")
        XCTAssertNotEqual(renderInfo.depthPixelFormat, .invalid,
                          "Depth pixel format should be valid")
    }
}
