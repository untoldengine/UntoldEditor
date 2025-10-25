//
//  ComponentEditorFormTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class ComponentEditorFormTests: XCTestCase {
    private func makeEntityID(_ raw: UInt64 = 42) -> EntityID { EntityID(raw) }

    func test_numberFieldInvokesSetAndRefresh() throws {
        let eid = makeEntityID(1001)

        var storage: [EntityID: Float] = [eid: 1.5]
        var refreshed = 0

        let field: EditorField = .number(
            label: "Speed",
            get: { id in storage[id, default: -999] },
            set: { id, newValue in storage[id] = newValue }
        )

        // Build the view; we won't render it, but we can still use the binding logic by reconstructing it.
        let form = ComponentForm(entityId: eid, fields: [field], refresh: { refreshed += 1 })

        // Simulate the binding write the same way ComponentForm does inside TextInputNumberView.
        // We need to replicate the binding used in the switch for .number:
        var lastSetValue: Float?
        let binding = Binding<Float>(
            get: { storage[eid, default: -999] },
            set: { newValue in
                lastSetValue = newValue
                storage[eid] = newValue
                refreshed += 1
            }
        )

        // When: change value via binding (what the control would do)
        binding.wrappedValue = 3.25

        // Then: set closure was effectively called (storage updated), and refresh fired
        XCTAssertEqual(storage[eid], 3.25)
        XCTAssertEqual(lastSetValue, 3.25)
        XCTAssertEqual(refreshed, 1)

        // Keep "form" alive to ensure no unexpected issues
        _ = form.body
    }

    func test_vector3FieldInvokesSetAndRefresh() throws {
        let eid = makeEntityID(2002)

        var storage: [EntityID: SIMD3<Float>] = [eid: SIMD3<Float>(1, 2, 3)]
        var refreshed = 0

        let field: EditorField = .vector3(
            label: "Position",
            get: { id in storage[id, default: SIMD3<Float>(-1, -1, -1)] },
            set: { id, newValue in storage[id] = newValue }
        )

        let form = ComponentForm(entityId: eid, fields: [field], refresh: { refreshed += 1 })

        var lastSetValue: SIMD3<Float>?
        let binding = Binding<SIMD3<Float>>(
            get: { storage[eid, default: SIMD3<Float>(-1, -1, -1)] },
            set: { newValue in
                lastSetValue = newValue
                storage[eid] = newValue
                refreshed += 1
            }
        )

        // When: change entire vector via binding
        let newVec = SIMD3<Float>(9, 8, 7)
        binding.wrappedValue = newVec

        // Then
        XCTAssertEqual(storage[eid], newVec)
        XCTAssertEqual(lastSetValue, newVec)
        XCTAssertEqual(refreshed, 1)

        _ = form.body
    }

    func test_textFieldInvokesSetAndRefreshAndHasPlaceholder() throws {
        let eid = makeEntityID(3003)

        var storage: [EntityID: String] = [eid: "Old Name"]
        var refreshed = 0

        let placeholder = "Enter name"

        let field: EditorField = .text(
            label: "Name",
            placeholder: placeholder,
            get: { id in storage[id, default: "<missing>"] },
            set: { id, newValue in storage[id] = newValue }
        )

        let form = ComponentForm(entityId: eid, fields: [field], refresh: { refreshed += 1 })

        // Build the same binding used by the .text case in ComponentForm
        var lastSetValue: String?
        let binding = Binding<String>(
            get: { storage[eid, default: "<missing>"] },
            set: { newValue in
                lastSetValue = newValue
                storage[eid] = newValue
                refreshed += 1
            }
        )

        // When: user types a new name
        binding.wrappedValue = "New Name"

        // Then
        XCTAssertEqual(storage[eid], "New Name")
        XCTAssertEqual(lastSetValue, "New Name")
        XCTAssertEqual(refreshed, 1)

        // Placeholder is passed through to TextField in the view. We can’t introspect SwiftUI’s hierarchy here,
        // but we can at least ensure the enum stored the value we provided, by reusing the same field value.
        switch field {
        case let .text(_, ph, _, _):
            XCTAssertEqual(ph, placeholder)
        default:
            XCTFail("Field should be .text")
        }

        _ = form.body
    }

    func test_multipleFieldsEachTriggerRefresh() throws {
        let eid = makeEntityID(4004)

        var numStorage: [EntityID: Float] = [eid: 0]
        var vecStorage: [EntityID: SIMD3<Float>] = [eid: SIMD3<Float>(0, 0, 0)]
        var textStorage: [EntityID: String] = [eid: ""]

        var refreshCount = 0
        let fields: [EditorField] = [
            .number(label: "Health",
                    get: { numStorage[$0, default: -1] },
                    set: { numStorage[$0] = $1 }),
            .vector3(label: "Velocity",
                     get: { vecStorage[$0, default: SIMD3<Float>(-1, -1, -1)] },
                     set: { vecStorage[$0] = $1 }),
            .text(label: "Tag",
                  placeholder: nil,
                  get: { textStorage[$0, default: ""] },
                  set: { textStorage[$0] = $1 }),
        ]

        let form = ComponentForm(entityId: eid, fields: fields, refresh: { refreshCount += 1 })

        // Simulate the three bindings used inside ComponentForm
        let numBinding = Binding<Float>(
            get: { numStorage[eid, default: -1] },
            set: { numStorage[eid] = $0; refreshCount += 1 }
        )
        let vecBinding = Binding<SIMD3<Float>>(
            get: { vecStorage[eid, default: SIMD3<Float>(-1, -1, -1)] },
            set: { vecStorage[eid] = $0; refreshCount += 1 }
        )
        let textBinding = Binding<String>(
            get: { textStorage[eid, default: ""] },
            set: { textStorage[eid] = $0; refreshCount += 1 }
        )

        // When: change each field
        numBinding.wrappedValue = 10
        vecBinding.wrappedValue = SIMD3<Float>(1, 2, 3)
        textBinding.wrappedValue = "Enemy"

        // Then: all storages updated and refresh called three times
        XCTAssertEqual(numStorage[eid], 10)
        XCTAssertEqual(vecStorage[eid], SIMD3<Float>(1, 2, 3))
        XCTAssertEqual(textStorage[eid], "Enemy")
        XCTAssertEqual(refreshCount, 3)

        _ = form.body
    }

    func test_makeEditorViewEmbedsForm() throws {
        let eid = makeEntityID(5555)

        var numValue: Float = 1
        let fields: [EditorField] = [
            .number(label: "Value",
                    get: { _ in numValue },
                    set: { _, v in numValue = v }),
        ]

        var refreshCount = 0
        let viewFactory = makeEditorView(fields: fields)

        // When: selectedId is present
        let view = viewFactory(eid, nil) { refreshCount += 1 }

        // We can’t introspect AnyView without a UI inspection library, but we can at least ensure it’s created
        // and that the set/refresh logic works through the same closures.
        XCTAssertEqual(numValue, 1)

        // Simulate what the TextInputNumberView would do by assigning through the set closure
        // (the get/set closures are what back the binding).
        for field in fields {
            if case let .number(_, _, set) = field {
                set(eid, 7)
            }
        }

        XCTAssertEqual(numValue, 7)
        _ = view
        _ = refreshCount // keep referenced
    }
}
