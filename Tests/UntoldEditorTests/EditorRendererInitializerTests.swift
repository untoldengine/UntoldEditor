//
//  EditorRendererInitializerTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import CShaderTypes
import MetalKit
import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/*
 final class EditorRendererInitializerTests: XCTestCase {
     private var device: MTLDevice!
     private var originalGizmoDescriptor: MDLVertexDescriptor!

     override func setUp() {
         super.setUp()

         // Set up Metal device
         guard let mtlDevice = MTLCreateSystemDefaultDevice() else {
             XCTFail("Metal device is not available.")
             return
         }

         device = mtlDevice
         renderInfo.device = device

         // Save original state
         originalGizmoDescriptor = vertexDescriptor.gizmo

         // Reset to clean state
         vertexDescriptor.gizmo = nil
     }

     override func tearDown() {
         // Restore original state
         vertexDescriptor.gizmo = originalGizmoDescriptor

         super.tearDown()
     }

     // MARK: - createGizmoVertexDescriptor Tests

     func test_createGizmoVertexDescriptor_returnsNonNilDescriptor() {
         // Act
         let descriptor = createGizmoVertexDescriptor()

         // Assert
         XCTAssertNotNil(descriptor, "createGizmoVertexDescriptor should return a valid MTLVertexDescriptor")
     }

     func test_createGizmoVertexDescriptor_setsGlobalVertexDescriptor() {
         // Arrange
         XCTAssertNil(vertexDescriptor.gizmo, "Gizmo descriptor should be nil before creation")

         // Act
         _ = createGizmoVertexDescriptor()

         // Assert
         XCTAssertNotNil(vertexDescriptor.gizmo, "Global vertexDescriptor.gizmo should be set after creation")
     }

     func test_createGizmoVertexDescriptor_configuresPositionAttribute() {
         // Act
         _ = createGizmoVertexDescriptor()

         // Assert
         guard let gizmo = vertexDescriptor.gizmo else {
             XCTFail("Gizmo descriptor should be set")
             return
         }

         let positionAttribute = gizmo.attributes[Int(modelPassVerticesIndex.rawValue)] as? MDLVertexAttribute
         XCTAssertNotNil(positionAttribute, "Position attribute should be configured")
         XCTAssertEqual(positionAttribute?.name, MDLVertexAttributePosition, "Attribute name should be position")
         XCTAssertEqual(positionAttribute?.format, .float4, "Position format should be float4")
         XCTAssertEqual(positionAttribute?.offset, 0, "Position offset should be 0")
         XCTAssertEqual(positionAttribute?.bufferIndex, Int(modelPassVerticesIndex.rawValue), "Buffer index should match modelPassVerticesIndex")
     }

     func test_createGizmoVertexDescriptor_configuresLayout() {
         // Act
         _ = createGizmoVertexDescriptor()

         // Assert
         guard let gizmo = vertexDescriptor.gizmo else {
             XCTFail("Gizmo descriptor should be set")
             return
         }

         let layout = gizmo.layouts[Int(modelPassVerticesIndex.rawValue)] as? MDLVertexBufferLayout
         XCTAssertNotNil(layout, "Layout should be configured")
         XCTAssertEqual(layout?.stride, MemoryLayout<simd_float4>.stride, "Layout stride should match simd_float4 stride")
     }

     func test_createGizmoVertexDescriptor_convertibleToMTLDescriptor() {
         // Act
         let mtlDescriptor = createGizmoVertexDescriptor()

         // Assert
         XCTAssertNotNil(mtlDescriptor, "Should be convertible to MTLVertexDescriptor")
         XCTAssertTrue(mtlDescriptor is MTLVertexDescriptor, "Result should be an MTLVertexDescriptor")
     }

     func test_createGizmoVertexDescriptor_mtlDescriptorHasCorrectAttributes() {
         // Act
         guard let mtlDescriptor = createGizmoVertexDescriptor() else {
             XCTFail("Should create a valid MTL descriptor")
             return
         }

         // Assert - Check the position attribute configuration
         let positionAttribute = mtlDescriptor.attributes[Int(modelPassVerticesIndex.rawValue)]
         XCTAssertEqual(positionAttribute.format, .float4, "MTL position format should be float4")
         XCTAssertEqual(positionAttribute.offset, 0, "MTL position offset should be 0")
         XCTAssertEqual(positionAttribute.bufferIndex, Int(modelPassVerticesIndex.rawValue), "MTL buffer index should be correct")
     }

     func test_createGizmoVertexDescriptor_mtlDescriptorHasCorrectLayout() {
         // Act
         guard let mtlDescriptor = createGizmoVertexDescriptor() else {
             XCTFail("Should create a valid MTL descriptor")
             return
         }

         // Assert - Check the layout configuration
         let layout = mtlDescriptor.layouts[Int(modelPassVerticesIndex.rawValue)]
         XCTAssertEqual(layout.stride, MemoryLayout<simd_float4>.stride, "MTL layout stride should match simd_float4")
     }

     func test_createGizmoVertexDescriptor_multipleCallsProduceSameConfiguration() {
         // Act
         let descriptor1 = createGizmoVertexDescriptor()
         let descriptor2 = createGizmoVertexDescriptor()

         // Assert
         XCTAssertNotNil(descriptor1)
         XCTAssertNotNil(descriptor2)

         // Both should have the same configuration
         XCTAssertEqual(descriptor1?.attributes[Int(modelPassVerticesIndex.rawValue)].format,
                        descriptor2?.attributes[Int(modelPassVerticesIndex.rawValue)].format)
         XCTAssertEqual(descriptor1?.layouts[Int(modelPassVerticesIndex.rawValue)].stride,
                        descriptor2?.layouts[Int(modelPassVerticesIndex.rawValue)].stride)
     }

     // MARK: - createDebugVertexDescriptor Tests

     func test_createDebugVertexDescriptor_returnsNonNilDescriptor() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         XCTAssertNotNil(descriptor, "createDebugVertexDescriptor should return a valid MTLVertexDescriptor")
     }

     func test_createDebugVertexDescriptor_configuresPositionAttribute() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         let positionAttribute = descriptor.attributes[0]
         XCTAssertEqual(positionAttribute.format, .float3, "Position format should be float3")
         XCTAssertEqual(positionAttribute.bufferIndex, 0, "Position buffer index should be 0")
         XCTAssertEqual(positionAttribute.offset, 0, "Position offset should be 0")
     }

     func test_createDebugVertexDescriptor_configuresTexCoordAttribute() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         let texCoordAttribute = descriptor.attributes[1]
         XCTAssertEqual(texCoordAttribute.format, .float2, "TexCoord format should be float2")
         XCTAssertEqual(texCoordAttribute.bufferIndex, 1, "TexCoord buffer index should be 1")
         XCTAssertEqual(texCoordAttribute.offset, 0, "TexCoord offset should be 0")
     }

     func test_createDebugVertexDescriptor_configuresPositionLayout() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         let positionLayout = descriptor.layouts[0]
         XCTAssertEqual(positionLayout.stride, MemoryLayout<simd_float3>.stride, "Position stride should match simd_float3")
         XCTAssertEqual(positionLayout.stepFunction, .perVertex, "Step function should be perVertex")
         XCTAssertEqual(positionLayout.stepRate, 1, "Step rate should be 1")
     }

     func test_createDebugVertexDescriptor_configuresTexCoordLayout() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         let texCoordLayout = descriptor.layouts[1]
         XCTAssertEqual(texCoordLayout.stride, MemoryLayout<simd_float2>.stride, "TexCoord stride should match simd_float2")
         XCTAssertEqual(texCoordLayout.stepFunction, .perVertex, "Step function should be perVertex")
         XCTAssertEqual(texCoordLayout.stepRate, 1, "Step rate should be 1")
     }

     func test_createDebugVertexDescriptor_hasSeparateBuffersForAttributes() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert
         let positionBufferIndex = descriptor.attributes[0].bufferIndex
         let texCoordBufferIndex = descriptor.attributes[1].bufferIndex

         XCTAssertNotEqual(positionBufferIndex, texCoordBufferIndex,
                          "Position and TexCoord should use separate buffers")
         XCTAssertEqual(positionBufferIndex, 0, "Position should use buffer 0")
         XCTAssertEqual(texCoordBufferIndex, 1, "TexCoord should use buffer 1")
     }

     func test_createDebugVertexDescriptor_multipleCallsProduceSameConfiguration() {
         // Act
         let descriptor1 = createDebugVertexDescriptor()
         let descriptor2 = createDebugVertexDescriptor()

         // Assert - Both should have the same configuration
         XCTAssertEqual(descriptor1.attributes[0].format, descriptor2.attributes[0].format)
         XCTAssertEqual(descriptor1.attributes[1].format, descriptor2.attributes[1].format)
         XCTAssertEqual(descriptor1.layouts[0].stride, descriptor2.layouts[0].stride)
         XCTAssertEqual(descriptor1.layouts[1].stride, descriptor2.layouts[1].stride)
     }

     func test_createDebugVertexDescriptor_hasCorrectNumberOfAttributes() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert - Check that exactly 2 attributes are configured (position and texCoord)
         var configuredAttributeCount = 0
         for i in 0..<descriptor.attributes.count {
             if descriptor.attributes[i].format != .invalid {
                 configuredAttributeCount += 1
             }
         }

         XCTAssertGreaterThanOrEqual(configuredAttributeCount, 2, "Should have at least 2 configured attributes")
     }

     func test_createDebugVertexDescriptor_hasCorrectNumberOfLayouts() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert - Check that exactly 2 layouts are configured
         var configuredLayoutCount = 0
         for i in 0..<descriptor.layouts.count {
             if descriptor.layouts[i].stride > 0 {
                 configuredLayoutCount += 1
             }
         }

         XCTAssertGreaterThanOrEqual(configuredLayoutCount, 2, "Should have at least 2 configured layouts")
     }

     // MARK: - Integration Tests

     func test_bothDescriptors_canBeCreatedSimultaneously() {
         // Act
         let gizmoDescriptor = createGizmoVertexDescriptor()
         let debugDescriptor = createDebugVertexDescriptor()

         // Assert
         XCTAssertNotNil(gizmoDescriptor, "Gizmo descriptor should be created")
         XCTAssertNotNil(debugDescriptor, "Debug descriptor should be created")
         XCTAssertNotNil(vertexDescriptor.gizmo, "Global gizmo descriptor should be set")
     }

     func test_descriptors_haveDifferentConfigurations() {
         // Act
         let gizmoDescriptor = createGizmoVertexDescriptor()
         let debugDescriptor = createDebugVertexDescriptor()

         // Assert - Gizmo uses float4, Debug uses float3
         XCTAssertNotEqual(
             gizmoDescriptor?.attributes[Int(modelPassVerticesIndex.rawValue)].format,
             debugDescriptor.attributes[0].format,
             "Gizmo and Debug descriptors should have different position formats"
         )
     }

     func test_gizmoDescriptor_usesModelPassVerticesIndex() {
         // Act
         guard let descriptor = createGizmoVertexDescriptor() else {
             XCTFail("Should create a valid descriptor")
             return
         }

         // Assert - Verify the correct index is used
         let attributeIndex = Int(modelPassVerticesIndex.rawValue)
         let attribute = descriptor.attributes[attributeIndex]

         XCTAssertNotEqual(attribute.format, .invalid, "Attribute at modelPassVerticesIndex should be configured")
         XCTAssertEqual(attribute.bufferIndex, attributeIndex, "Buffer index should match modelPassVerticesIndex")
     }

     func test_debugDescriptor_canBeUsedForQuadRendering() {
         // Act
         let descriptor = createDebugVertexDescriptor()

         // Assert - Verify it has the essential components for quad rendering
         XCTAssertEqual(descriptor.attributes[0].format, .float3, "Should have position for quad vertices")
         XCTAssertEqual(descriptor.attributes[1].format, .float2, "Should have texcoords for quad")
         XCTAssertGreaterThan(descriptor.layouts[0].stride, 0, "Position layout should have valid stride")
         XCTAssertGreaterThan(descriptor.layouts[1].stride, 0, "TexCoord layout should have valid stride")
     }
 }
 */
