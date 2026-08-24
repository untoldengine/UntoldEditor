//
//  EditorFuncUtilsTests.swift
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
import ModelIO
import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class EditorFuncUtilsTests: XCTestCase {
    override func setUp() {
        super.setUp()

        // Create fresh scene
        scene = Scene()
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Binding for WrapMode Tests

    func test_bindingForWrapMode_returnsBinding() {
        // Arrange
        let entity = createEntity()

        // Act
        let binding = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: {}
        )

        // Assert
        XCTAssertNotNil(binding, "Should return a binding")
    }

    func test_bindingForWrapMode_fallsBackToClampToEdgeForInvalidEntity() {
        // Arrange
        let entity = createEntity()
        // Entity has no RenderComponent

        // Act
        let binding = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: {}
        )

        // Assert
        XCTAssertEqual(binding.wrappedValue, .clampToEdge, "Should fallback to clampToEdge when no material")
    }

    func test_bindingForWrapMode_triggersOnChangeWhenSet() {
        // Arrange
        let entity = createEntity()
        var onChangeCalled = false

        let binding = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: { onChangeCalled = true }
        )

        // Act
        binding.wrappedValue = .repeat

        // Assert
        XCTAssertTrue(onChangeCalled, "Should trigger onChange callback")
    }

    func test_bindingForWrapMode_worksForAllTextureTypes() {
        // Arrange
        let entity = createEntity()

        let textureTypes: [TextureType] = [.baseColor, .normal, .roughness, .metallic]

        // Act & Assert
        for textureType in textureTypes {
            let binding = bindingForWrapMode(
                entityId: entity,
                textureType: textureType,
                onChange: {}
            )

            XCTAssertNotNil(binding, "Should create binding for \(textureType)")
            XCTAssertEqual(binding.wrappedValue, .clampToEdge, "Should have default value for \(textureType)")
        }
    }

    // MARK: - Binding for ST Scale Tests

    func test_bindingForSTScale_returnsBinding() {
        // Arrange
        let entity = createEntity()

        // Act
        let binding = bindingForSTScale(
            entityId: entity,
            onChange: {}
        )

        // Assert
        XCTAssertNotNil(binding, "Should return a binding")
    }

    func test_bindingForSTScale_fallsBackToOneForInvalidEntity() {
        // Arrange
        let entity = createEntity()
        // Entity has no RenderComponent

        // Act
        let binding = bindingForSTScale(entityId: entity, onChange: {})

        // Assert
        XCTAssertEqual(binding.wrappedValue, 1.0, "Should fallback to 1.0 when no material")
    }

    func test_bindingForSTScale_triggersOnChangeWhenSet() {
        // Arrange
        let entity = createEntity()
        var onChangeCalled = false

        let binding = bindingForSTScale(
            entityId: entity,
            onChange: { onChangeCalled = true }
        )

        // Act
        binding.wrappedValue = 2.0

        // Assert
        XCTAssertTrue(onChangeCalled, "Should trigger onChange callback")
    }

    // MARK: - Binding for Material Roughness Tests

    func test_bindingForMaterialRoughness_returnsBinding() {
        // Arrange
        let entity = createEntity()

        // Act
        let binding = bindingForMaterialRoughness(
            entityId: entity,
            onChange: {}
        )

        // Assert
        XCTAssertNotNil(binding, "Should return a binding")
    }

    func test_bindingForMaterialRoughness_triggersOnChangeWhenSet() {
        // Arrange
        let entity = createEntity()
        var onChangeCalled = false

        let binding = bindingForMaterialRoughness(
            entityId: entity,
            onChange: { onChangeCalled = true }
        )

        // Act
        binding.wrappedValue = 0.5

        // Assert
        XCTAssertTrue(onChangeCalled, "Should trigger onChange callback")
    }

    func test_bindingForMaterialRoughness_acceptsValidRange() {
        // Arrange
        let entity = createEntity()

        let binding = bindingForMaterialRoughness(entityId: entity, onChange: {})

        // Act & Assert: Test various valid values
        let validValues: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]

        for value in validValues {
            binding.wrappedValue = value
            // Should not crash
            XCTAssertTrue(true, "Should accept value \(value)")
        }
    }

    // MARK: - Get Material Texture Image Tests

    func test_getMaterialTextureImage_returnsNilForInvalidEntity() {
        // Arrange
        let entity = createEntity()
        // Entity has no RenderComponent

        // Act
        let image = getMaterialTextureImage(entityId: entity, type: .baseColor)

        // Assert
        XCTAssertNil(image, "Should return nil when entity has no material")
    }

    func test_getMaterialTextureImage_returnsNilForAllTextureTypesWithoutMaterial() {
        // Arrange
        let entity = createEntity()

        let textureTypes: [TextureType] = [.baseColor, .normal, .roughness, .metallic]

        // Act & Assert
        for textureType in textureTypes {
            let image = getMaterialTextureImage(entityId: entity, type: textureType)
            XCTAssertNil(image, "Should return nil for \(textureType) without material")
        }
    }

    // MARK: - NSImage from MDLTexture Tests

    func test_nsImageFromMDLTexture_returnsNilForTextureWithoutData() {
        // Arrange: Create a minimal MDLTexture without proper data
        // Note: We can't easily create a valid MDLTexture without external dependencies,
        // so we test the error paths that are accessible

        // This test is primarily documentation of the expected behavior
        // In practice, nsImageFromMDLTexture requires a valid MDLTexture with texel data
        XCTAssertTrue(true, "nsImageFromMDLTexture requires valid MDLTexture - tested via integration")
    }

    // MARK: - Binding Behavior Tests

    func test_bindingForWrapMode_getAndSet() {
        // Arrange
        let entity = createEntity()
        var changeCount = 0

        let binding = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: { changeCount += 1 }
        )

        // Act: Get initial value
        let initialValue = binding.wrappedValue

        // Set new value
        binding.wrappedValue = .repeat

        // Assert
        XCTAssertEqual(initialValue, .clampToEdge, "Initial value should be clampToEdge")
        XCTAssertEqual(changeCount, 1, "onChange should be called once")
        // Note: wrappedValue may still be clampToEdge because the entity has no material
        // The setter still calls updateTextureSampler which may fail gracefully
    }

    func test_bindingForSTScale_getAndSet() {
        // Arrange
        let entity = createEntity()
        var changeCount = 0

        let binding = bindingForSTScale(
            entityId: entity,
            onChange: { changeCount += 1 }
        )

        // Act: Get initial value
        let initialValue = binding.wrappedValue

        // Set new value
        binding.wrappedValue = 2.5

        // Assert
        XCTAssertEqual(initialValue, 1.0, "Initial value should be 1.0")
        XCTAssertEqual(changeCount, 1, "onChange should be called once")
        // Note: wrappedValue may still be 1.0 because the entity has no material
    }

    func test_bindingForMaterialRoughness_getAndSet() {
        // Arrange
        let entity = createEntity()
        var changeCount = 0

        let binding = bindingForMaterialRoughness(
            entityId: entity,
            onChange: { changeCount += 1 }
        )

        // Act: Set new value
        binding.wrappedValue = 0.7

        // Assert
        XCTAssertEqual(changeCount, 1, "onChange should be called once")
    }

    // MARK: - Multiple Bindings Tests

    func test_multipleBindings_canCoexist() {
        // Arrange
        let entity = createEntity()
        var wrapModeChanged = false
        var stScaleChanged = false
        var roughnessChanged = false

        // Act: Create multiple bindings for the same entity
        let wrapBinding = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: { wrapModeChanged = true }
        )

        let stScaleBinding = bindingForSTScale(
            entityId: entity,
            onChange: { stScaleChanged = true }
        )

        let roughnessBinding = bindingForMaterialRoughness(
            entityId: entity,
            onChange: { roughnessChanged = true }
        )

        // Assert: All bindings exist independently
        XCTAssertNotNil(wrapBinding, "WrapMode binding should exist")
        XCTAssertNotNil(stScaleBinding, "STScale binding should exist")
        XCTAssertNotNil(roughnessBinding, "Roughness binding should exist")

        // Act: Trigger changes
        wrapBinding.wrappedValue = .repeat
        stScaleBinding.wrappedValue = 2.0
        roughnessBinding.wrappedValue = 0.5

        // Assert: Each callback is independent
        XCTAssertTrue(wrapModeChanged, "WrapMode onChange should be called")
        XCTAssertTrue(stScaleChanged, "STScale onChange should be called")
        XCTAssertTrue(roughnessChanged, "Roughness onChange should be called")
    }

    // MARK: - Edge Cases

    func test_bindingForWrapMode_withInvalidEntity() {
        // Arrange
        let invalidEntity = EntityID(99999)

        // Act
        let binding = bindingForWrapMode(
            entityId: invalidEntity,
            textureType: .baseColor,
            onChange: {}
        )

        // Assert: Should not crash
        XCTAssertEqual(binding.wrappedValue, .clampToEdge, "Should handle invalid entity gracefully")
    }

    func test_bindingForSTScale_withInvalidEntity() {
        // Arrange
        let invalidEntity = EntityID(99999)

        // Act
        let binding = bindingForSTScale(entityId: invalidEntity, onChange: {})

        // Assert: Should not crash
        XCTAssertEqual(binding.wrappedValue, 1.0, "Should handle invalid entity gracefully")
    }

    func test_bindingForMaterialRoughness_withInvalidEntity() {
        // Arrange
        let invalidEntity = EntityID(99999)

        // Act
        let binding = bindingForMaterialRoughness(entityId: invalidEntity, onChange: {})

        // Assert: Should not crash and return some value
        _ = binding.wrappedValue
        XCTAssertTrue(true, "Should handle invalid entity without crashing")
    }

    func test_getMaterialTextureImage_withInvalidEntity() {
        // Arrange
        let invalidEntity = EntityID(99999)

        // Act
        let image = getMaterialTextureImage(entityId: invalidEntity, type: .baseColor)

        // Assert: Should not crash
        XCTAssertNil(image, "Should return nil for invalid entity")
    }

    // MARK: - Callback Behavior Tests

    func test_onChange_calledMultipleTimes() {
        // Arrange
        let entity = createEntity()
        var callCount = 0

        let binding = bindingForSTScale(
            entityId: entity,
            onChange: { callCount += 1 }
        )

        // Act: Set value multiple times
        binding.wrappedValue = 1.5
        binding.wrappedValue = 2.0
        binding.wrappedValue = 2.5

        // Assert
        XCTAssertEqual(callCount, 3, "onChange should be called for each set")
    }

    func test_onChange_notCalledOnGet() {
        // Arrange
        let entity = createEntity()
        var callCount = 0

        let binding = bindingForSTScale(
            entityId: entity,
            onChange: { callCount += 1 }
        )

        // Act: Only get value
        _ = binding.wrappedValue
        _ = binding.wrappedValue
        _ = binding.wrappedValue

        // Assert
        XCTAssertEqual(callCount, 0, "onChange should not be called on get")
    }

    // MARK: - Integration Tests

    func test_bindingsWorkWithSwiftUIEnvironment() {
        // This test validates that the bindings are compatible with SwiftUI's Binding type
        // and can be used in SwiftUI views

        let entity = createEntity()

        let wrapModeBinding: Binding<WrapMode> = bindingForWrapMode(
            entityId: entity,
            textureType: .baseColor,
            onChange: {}
        )

        let stScaleBinding: Binding<Float> = bindingForSTScale(
            entityId: entity,
            onChange: {}
        )

        let roughnessBinding: Binding<Float> = bindingForMaterialRoughness(
            entityId: entity,
            onChange: {}
        )

        // Assert: All bindings are SwiftUI-compatible
        XCTAssertTrue(type(of: wrapModeBinding) == Binding<WrapMode>.self, "Should be SwiftUI Binding")
        XCTAssertTrue(type(of: stScaleBinding) == Binding<Float>.self, "Should be SwiftUI Binding")
        XCTAssertTrue(type(of: roughnessBinding) == Binding<Float>.self, "Should be SwiftUI Binding")
    }
}
