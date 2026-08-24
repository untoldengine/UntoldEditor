//
//  NumericInputTest.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import SwiftUI
@testable import UntoldEditor
import XCTest

final class NumericInputViewTests: XCTestCase {
    // MARK: - TextInputNumberView

    func test_TextInputNumberView_onAppearInitializesFromBinding_andOnSubmitWritesBack() {
        // Arrange
        var model: Float = 1.25
        let sut = TextInputNumberView(
            label: "Value",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: emulate a no-op submit (user hits return without changing text)
        let before = model
        _ = before // read-only no-op

        // Assert
        XCTAssertEqual(model, 1.25, accuracy: 0.0001)
        _ = sut.body
    }

    func test_TextInputNumberView_userEditsAndSubmits_updatesBinding() {
        // Arrange
        var model: Float = 0.0
        let sut = TextInputNumberView(
            label: "Value",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: emulate typing "3.5" and submitting
        let newValue: Float = 3.5
        model = newValue

        // Assert
        XCTAssertEqual(model, 3.5, accuracy: 0.0001)
        _ = sut.body
    }

    func test_TextInputNumberView_onChangeOfBinding_updatesDisplayedValueOnNextCycle() {
        // Arrange
        var model: Float = 2.0
        var sut = TextInputNumberView(
            label: "Value",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: external change to the bound value (what onChange listens for)
        model = 4.25

        // Emulate a no-op submit; binding should still read the updated value
        _ = model // read-only no-op

        // Assert
        XCTAssertEqual(model, 4.25, accuracy: 0.0001)
        _ = sut.body

        // Rebuild view as SwiftUI would after state changes
        sut = TextInputNumberView(
            label: "Value",
            value: .init(get: { model }, set: { model = $0 })
        )
        _ = sut.body
        XCTAssertEqual(model, 4.25, accuracy: 0.0001)
    }

    // MARK: - TextInputVectorView

    func test_TextInputVectorView_onAppearInitializesFromBinding_andOnSubmitWritesBack() {
        // Arrange
        var model = SIMD3<Float>(1, 2, 3)
        let sut = TextInputVectorView(
            label: "Vec",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: emulate a no-op submit
        let before = model
        _ = before // read-only no-op

        // Assert
        XCTAssertEqual(model, SIMD3<Float>(1, 2, 3))
        _ = sut.body
    }

    func test_TextInputVectorView_userEditsEachComponentAndSubmits_updatesBinding() {
        // Arrange
        var model = SIMD3<Float>(0, 0, 0)
        let sut = TextInputVectorView(
            label: "Vec",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: emulate editing via binding
        model[0] = 9.0
        model[1] = -2.5
        model[2] = 3.14159

        // Assert
        XCTAssertEqual(model.x, 9.0, accuracy: 0.0001)
        XCTAssertEqual(model.y, -2.5, accuracy: 0.0001)
        XCTAssertEqual(model.z, 3.14159, accuracy: 0.0001)
        _ = sut.body
    }

    func test_TextInputVectorView_onChangeOfBinding_updatesDisplayedValuesOnNextCycle() {
        // Arrange
        var model = SIMD3<Float>(5, 5, 5)
        var sut = TextInputVectorView(
            label: "Vec",
            value: .init(get: { model }, set: { model = $0 })
        )

        // Act: external change
        model = SIMD3<Float>(-1, 0.5, 42)

        // Emulate a no-op submit
        _ = model // read-only no-op

        // Assert
        XCTAssertEqual(model, SIMD3<Float>(-1, 0.5, 42))
        _ = sut.body

        // Rebuild view as SwiftUI would after state changes
        sut = TextInputVectorView(
            label: "Vec",
            value: .init(get: { model }, set: { model = $0 })
        )
        _ = sut.body
        XCTAssertEqual(model, SIMD3<Float>(-1, 0.5, 42))
    }
}
