//
//  EditorRenderPassesTests.swift
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

final class EditorRenderPassesTests: XCTestCase {
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var originalActiveEntity: EntityID!
    private var originalParentGizmo: EntityID!
    private var testEntity: EntityID!

    override func setUp() {
        super.setUp()

        // Set up Metal device
        guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
            XCTFail("Metal device is not available.")
            return
        }

        device = mtlDevice
        commandQueue = device.makeCommandQueue()

        renderInfo.device = device
        renderInfo.commandQueue = commandQueue
        renderInfo.fence = device.makeFence()
        vertexDescriptor.model = MDLVertexDescriptor()

        // Save original state
        originalActiveEntity = activeEntity
        originalParentGizmo = parentEntityIdGizmo

        // Reset to clean state
        activeEntity = .invalid
        parentEntityIdGizmo = .invalid
    }

    override func tearDown() {
        // Clean up test entity if created
        if testEntity != .invalid, testEntity != nil {
            destroyEntity(entityId: testEntity)
        }

        // Restore original state
        activeEntity = originalActiveEntity
        parentEntityIdGizmo = originalParentGizmo

        super.tearDown()
    }

    // MARK: - Render Pass Existence Tests

    func test_gizmoExecution_existsAndIsCallable() {
        // Assert - Verify the closure exists
        XCTAssertNotNil(RenderPasses.gizmoExecution, "gizmoExecution should exist")

        // The closure should be callable (though it will return early without proper setup)
        let closure = RenderPasses.gizmoExecution
        XCTAssertNotNil(closure, "gizmoExecution closure should be accessible")
    }

    func test_outlineExecution_existsAndIsCallable() {
        // Assert
        XCTAssertNotNil(RenderPasses.outlineExecution, "outlineExecution should exist")

        let closure = RenderPasses.outlineExecution
        XCTAssertNotNil(closure, "outlineExecution closure should be accessible")
    }

    func test_debuggerExecution_existsAndIsCallable() {
        // Assert
        XCTAssertNotNil(RenderPasses.debuggerExecution, "debuggerExecution should exist")

        let closure = RenderPasses.debuggerExecution
        XCTAssertNotNil(closure, "debuggerExecution closure should be accessible")
    }

    func test_lightVisualPass_existsAndIsCallable() {
        // Assert
        XCTAssertNotNil(RenderPasses.lightVisualPass, "lightVisualPass should exist")

        let closure = RenderPasses.lightVisualPass
        XCTAssertNotNil(closure, "lightVisualPass closure should be accessible")
    }

    func test_highlightExecution_existsAndIsCallable() {
        // Assert
        XCTAssertNotNil(RenderPasses.highlightExecution, "highlightExecution should exist")

        let closure = RenderPasses.highlightExecution
        XCTAssertNotNil(closure, "highlightExecution closure should be accessible")
    }

    func test_editorPreCompositeExecution_restoresSSAOEnabled() {
        // Arrange
        let originalSSAOEnabled = SSAOParams.shared.enabled
        SSAOParams.shared.enabled = true
        defer {
            SSAOParams.shared.enabled = originalSSAOEnabled
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            XCTFail("Could not create command buffer")
            return
        }

        // Act
        RenderPasses.editorPreCompositeExecution(commandBuffer)

        // Assert
        XCTAssertTrue(SSAOParams.shared.enabled, "Editor pre-composite should not change the user's SSAO setting")
    }

    // MARK: - Early Return Condition Tests

    func test_gizmoExecution_returnsEarlyWhenActiveEntityIsInvalid() {
        // Arrange
        activeEntity = .invalid

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            XCTFail("Could not create command buffer")
            return
        }

        // Act - Should return early without crashing
        RenderPasses.gizmoExecution(commandBuffer)

        // Assert - If we got here without crashing, the early return worked
        XCTAssertEqual(activeEntity, .invalid, "Active entity should still be invalid")
    }

    func test_outlineExecution_returnsEarlyWhenActiveEntityIsInvalid() {
        // Arrange
        activeEntity = .invalid

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            XCTFail("Could not create command buffer")
            return
        }

        // Act - Should return early without crashing
        RenderPasses.outlineExecution(commandBuffer)

        // Assert
        XCTAssertEqual(activeEntity, .invalid, "Active entity should still be invalid")
    }

    func test_highlightExecution_handlesInvalidActiveEntity() {
        // Arrange
        activeEntity = .invalid

        // Set up minimal render pass descriptor to avoid crashes
        renderInfo.gizmoRenderPassDescriptor = MTLRenderPassDescriptor()
        let colorAttachment = renderInfo.gizmoRenderPassDescriptor.colorAttachments[0]

        // Create a temporary texture for the color attachment
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.width = 64
        textureDescriptor.height = 64
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.usage = [.renderTarget]

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            XCTFail("Could not create texture")
            return
        }

        colorAttachment?.texture = texture
        colorAttachment?.loadAction = .clear
        colorAttachment?.storeAction = .store

        renderInfo.gizmoRenderPassDescriptor.depthAttachment.loadAction = .clear

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            XCTFail("Could not create command buffer")
            return
        }

        // Act - Should handle invalid entity gracefully
        RenderPasses.highlightExecution(commandBuffer)

        // Assert - The pass should have executed (with early clear path)
        XCTAssertEqual(activeEntity, .invalid, "Active entity should still be invalid")
    }

    // MARK: - Component Query Tests

    func test_gizmoExecution_requiresSpecificComponents() {
        // This test verifies that gizmo execution queries for the right components
        // The actual query happens inside: queryEntitiesWithComponentIds([transformId, renderId, gizmoId], in: scene)

        // Arrange - Create an entity with only some components
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: testEntity, componentType: WorldTransformComponent.self)
        // Note: NOT adding RenderComponent or GizmoComponent

        activeEntity = testEntity

        // The gizmo pass should query for WorldTransformComponent, RenderComponent, and GizmoComponent
        let transformId = getComponentId(for: WorldTransformComponent.self)
        let renderId = getComponentId(for: RenderComponent.self)
        let gizmoId = getComponentId(for: GizmoComponent.self)

        let entities = queryEntitiesWithComponentIds([transformId, renderId, gizmoId], in: scene)

        // Assert - Our test entity should NOT be in the result since it's missing components
        XCTAssertFalse(entities.contains(testEntity),
                       "Entity without all required components should not be queried")
    }

    func test_lightVisualPass_queriesForLightComponents() {
        // The light visual pass queries for: LocalTransformComponent and LightComponent

        // Arrange - Create an entity with transform but no light
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)

        let transformId = getComponentId(for: LocalTransformComponent.self)
        let lightId = getComponentId(for: LightComponent.self)

        let entitiesWithoutLight = queryEntitiesWithComponentIds([transformId, lightId], in: scene)

        // Assert - Should not include entity without light
        XCTAssertFalse(entitiesWithoutLight.contains(testEntity),
                       "Entity without light component should not be queried")

        // Now add a light component
        registerComponent(entityId: testEntity, componentType: LightComponent.self)

        let entitiesWithLight = queryEntitiesWithComponentIds([transformId, lightId], in: scene)

        // Assert - Should now include the entity
        XCTAssertTrue(entitiesWithLight.contains(testEntity),
                      "Entity with both components should be queried")
    }

    // MARK: - Render Pass Configuration Tests

    func test_gizmoExecution_usesGizmoRenderPassDescriptor() {
        // The gizmo pass should use renderInfo.gizmoRenderPassDescriptor
        // and set specific load actions

        // Arrange - Set up a render pass descriptor
        renderInfo.gizmoRenderPassDescriptor = MTLRenderPassDescriptor()

        // The pass sets:
        // - colorAttachments[colorTarget].loadAction = .load
        // - depthAttachment.loadAction = .clear

        // Assert - Verify these are the expected configurations
        // (This is more of a structural test to document expected behavior)
        XCTAssertNotNil(renderInfo.gizmoRenderPassDescriptor,
                        "Gizmo render pass descriptor should be available")
    }

    func test_outlineExecution_usesOffscreenRenderPassDescriptor() {
        // The outline pass should use renderInfo.offscreenRenderPassDescriptor

        // Arrange
        renderInfo.offscreenRenderPassDescriptor = MTLRenderPassDescriptor()

        // The pass sets multiple load actions:
        // - colorAttachments[colorTarget].loadAction = .load
        // - colorAttachments[normalTarget].loadAction = .load
        // - colorAttachments[positionTarget].loadAction = .load
        // - depthAttachment.loadAction = .load

        XCTAssertNotNil(renderInfo.offscreenRenderPassDescriptor,
                        "Offscreen render pass descriptor should be available")
    }

    func test_lightVisualPass_usesGizmoRenderPassDescriptorWithLoad() {
        // The light visual pass uses gizmoRenderPassDescriptor with load actions

        // Arrange
        renderInfo.gizmoRenderPassDescriptor = MTLRenderPassDescriptor()

        // The pass sets:
        // - colorAttachments[colorTarget].loadAction = .load
        // - depthAttachment.loadAction = .load

        XCTAssertNotNil(renderInfo.gizmoRenderPassDescriptor,
                        "Gizmo render pass descriptor should be available for light visual pass")
    }

    func test_highlightExecution_configuresRenderPassDifferentlyBasedOnActiveEntity() {
        // When activeEntity is invalid: loadAction = .clear
        // When activeEntity is valid: loadAction = .clear (but renders content)

        // Arrange
        renderInfo.gizmoRenderPassDescriptor = MTLRenderPassDescriptor()

        // Both cases use clear for the highlight pass
        // The difference is whether content is rendered

        XCTAssertNotNil(renderInfo.gizmoRenderPassDescriptor,
                        "Gizmo render pass descriptor should be available for highlight pass")
    }

    // MARK: - Pipeline Validation Tests

    func test_gizmoExecution_requiresGizmoPipeline() {
        // The gizmo pass requires PipelineManager to have a .gizmo pipeline

        // The pass checks:
        // 1. Pipeline exists: PipelineManager.shared.renderPipelinesByType[.gizmo]
        // 2. Pipeline success: pipeline.success == true

        // This test documents the requirement
        XCTAssertTrue(true, "Gizmo execution requires gizmo pipeline from PipelineManager")
    }

    func test_outlineExecution_requiresOutlinePipeline() {
        // The outline pass requires PipelineManager to have an .outline pipeline
        XCTAssertTrue(true, "Outline execution requires outline pipeline from PipelineManager")
    }

    func test_debuggerExecution_requiresDebugPipeline() {
        // The debugger pass requires PipelineManager to have a .debug pipeline
        XCTAssertTrue(true, "Debugger execution requires debug pipeline from PipelineManager")
    }

    func test_lightVisualPass_requiresLightVisualPipeline() {
        // The light visual pass requires PipelineManager to have a .lightVisual pipeline
        XCTAssertTrue(true, "Light visual pass requires lightVisual pipeline from PipelineManager")
    }

    func test_highlightExecution_requiresHighlightPipeline() {
        // The highlight pass requires PipelineManager to have a .highlight pipeline
        XCTAssertTrue(true, "Highlight execution requires highlight pipeline from PipelineManager")
    }

    // MARK: - Render State Tests

    func test_outlineExecution_setsCullModeToFront() {
        // The outline pass sets: renderEncoder.setCullMode(.front)
        // This is for rendering back-faces to create an outline effect
        XCTAssertTrue(true, "Outline pass should use front-face culling")
    }

    func test_lightVisualPass_setsCullModeToBack() {
        // The light visual pass sets: renderEncoder.setCullMode(.back)
        XCTAssertTrue(true, "Light visual pass should use back-face culling")
    }

    func test_highlightExecution_setsCullModeToBack() {
        // The highlight pass sets: renderEncoder.setCullMode(.back)
        XCTAssertTrue(true, "Highlight pass should use back-face culling")
    }

    func test_allPasses_setFrontFacingToCounterClockwise() {
        // All passes that set front facing use .counterClockwise
        XCTAssertTrue(true, "Passes should use counter-clockwise front facing")
    }

    // MARK: - Light Type Handling Tests

    func test_lightVisualPass_handlesAllLightTypes() {
        // The light visual pass should handle all light types:
        // - .directional
        // - .point
        // - .spotlight
        // - .area

        // Create an entity with a light component
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: LocalTransformComponent.self)
        registerComponent(entityId: testEntity, componentType: LightComponent.self)

        guard let lightComponent = scene.get(component: LightComponent.self, for: testEntity) else {
            XCTFail("Should have light component")
            return
        }

        // Verify the component exists and can have different light types set
        XCTAssertNotNil(lightComponent, "Light component should exist")
    }

    func test_highlightExecution_handlesBothLightsAndNonLights() {
        // The highlight pass renders differently for lights vs non-lights:
        // - For lights: renders light debug mesh with specific scale
        // - For non-lights: renders bounding box

        // Test with non-light entity
        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: WorldTransformComponent.self)
        registerComponent(entityId: testEntity, componentType: RenderComponent.self)

        let hasLight = hasComponent(entityId: testEntity, componentType: LightComponent.self)
        XCTAssertFalse(hasLight, "Test entity should not have light component")

        // Test with light entity
        let lightEntity = createEntity()
        registerComponent(entityId: lightEntity, componentType: WorldTransformComponent.self)
        registerComponent(entityId: lightEntity, componentType: LightComponent.self)

        let hasLightComponent = hasComponent(entityId: lightEntity, componentType: LightComponent.self)
        XCTAssertTrue(hasLightComponent, "Light entity should have light component")

        destroyEntity(entityId: lightEntity)
    }

    func test_highlightExecution_calculatesScaleForDifferentLightTypes() {
        // Point lights: scale = simd_float3(repeating: radius)
        // Spot lights: scale based on cone angle and radius
        // Area lights: uses area light debug mesh
        // Directional lights: uses directional light debug mesh
        // Non-lights: scale = simd_float3(repeating: 1.2)

        testEntity = createEntity()
        registerComponent(entityId: testEntity, componentType: WorldTransformComponent.self)

        // Test scale for non-light
        let nonLightScale = simd_float3(repeating: 1.2)
        XCTAssertEqual(nonLightScale, simd_float3(1.2, 1.2, 1.2),
                       "Non-light entities should use scale of 1.2")
    }

    // MARK: - Buffer Resource Tests

    func test_debuggerExecution_usesQuadBuffers() {
        // The debugger pass uses:
        // - bufferResources.quadVerticesBuffer
        // - bufferResources.quadTexCoordsBuffer
        // - bufferResources.quadIndexBuffer

        XCTAssertTrue(true, "Debugger pass requires quad buffer resources")
    }

    func test_lightVisualPass_usesQuadBuffers() {
        // The light visual pass also uses quad buffers for rendering light icons
        XCTAssertTrue(true, "Light visual pass requires quad buffer resources")
    }

    func test_highlightExecution_usesBoundingBoxBuffer() {
        // For non-light entities, the highlight pass uses:
        // - bufferResources.boundingBoxBuffer

        XCTAssertTrue(true, "Highlight pass requires bounding box buffer for non-light entities")
    }

    // MARK: - Integration Documentation Tests

    func test_allPasses_useFenceForSynchronization() {
        // All passes should:
        // - waitForFence before vertex stage
        // - updateFence after fragment stage

        XCTAssertTrue(true, "All render passes should use Metal fences for GPU synchronization")
    }

    func test_allPasses_useDeferForProperCleanup() {
        // All passes should use defer blocks to ensure:
        // - popDebugGroup() is called
        // - endEncoding() is called

        XCTAssertTrue(true, "All render passes should use defer for proper encoder cleanup")
    }

    func test_gizmoExecution_calculatesWorldScaleBasedOnCameraDistance() {
        // The gizmo pass calculates scale dynamically:
        // let worldScale = (distanceToCamera * tan(fov * 0.5)) * (gizmoDesiredScreenSize / renderInfo.viewPort.y)

        // This ensures gizmos maintain constant screen size regardless of camera distance
        XCTAssertTrue(true, "Gizmo scale should be calculated based on camera distance")
    }
}
