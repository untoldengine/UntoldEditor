//
//  ToolbarViewTests.swift
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

#if canImport(AppKit)
    final class ToolbarViewTests: XCTestCase {
        // Build a ToolbarView with closures that flip flags so we can assert wiring.
        private func makeSUT(
            selectionManager: SelectionManager = SelectionManager(),
            onSaveCalled: UnsafeMutablePointer<Bool>,
            onLoadCalled: UnsafeMutablePointer<Bool>,
            onClearCalled: UnsafeMutablePointer<Bool>,
            onCameraSaveCalled _: UnsafeMutablePointer<Bool>,
            onPlayToggledValues: UnsafeMutablePointer<[Bool]>,
            onDirLightCalled: UnsafeMutablePointer<Bool>,
            onPointLightCalled: UnsafeMutablePointer<Bool>,
            onSpotLightCalled: UnsafeMutablePointer<Bool>,
            onAreaLightCalled: UnsafeMutablePointer<Bool>
        ) -> ToolbarView {
            ToolbarView(
                selectionManager: selectionManager,
                onSave: { onSaveCalled.pointee = true },
                onLoad: { onLoadCalled.pointee = true },
                onClear: { onClearCalled.pointee = true },
                onPlayToggled: { value in onPlayToggledValues.pointee.append(value) },
                dirLightCreate: { onDirLightCalled.pointee = true },
                pointLightCreate: { onPointLightCalled.pointee = true },
                spotLightCreate: { onSpotLightCalled.pointee = true },
                areaLightCreate: { onAreaLightCalled.pointee = true }
            )
        }

        func test_actionsAreWired_up() {
            var onSave = false
            var onLoad = false
            var onClear = false
            var onCameraSave = false
            var playValues: [Bool] = []
            var onDir = false
            var onPoint = false
            var onSpot = false
            var onArea = false

            let sut = makeSUT(
                onSaveCalled: &onSave,
                onLoadCalled: &onLoad,
                onClearCalled: &onClear,
                onCameraSaveCalled: &onCameraSave,
                onPlayToggledValues: &playValues,
                onDirLightCalled: &onDir,
                onPointLightCalled: &onPoint,
                onSpotLightCalled: &onSpot,
                onAreaLightCalled: &onArea
            )

            // We cannot programmatically tap SwiftUI Buttons without a host and introspection.
            // Instead, assert that injected closures can be called and flip their flags.
            sut.onSave()
            sut.onLoad()
            sut.onClear()
            sut.dirLightCreate()
            sut.pointLightCreate()
            sut.spotLightCreate()
            sut.areaLightCreate()

            XCTAssertTrue(onSave, "onSave should be wired.")
            XCTAssertTrue(onLoad, "onLoad should be wired.")
            XCTAssertTrue(onClear, "onClear should be wired.")
            XCTAssertTrue(onDir, "dirLightCreate should be wired.")
            XCTAssertTrue(onPoint, "pointLightCreate should be wired.")
            XCTAssertTrue(onSpot, "spotLightCreate should be wired.")
            XCTAssertTrue(onArea, "areaLightCreate should be wired.")

            // For play toggle, verify the closure records values we pass.
            // Since @State is internal, we mimic the button behavior by calling the closure directly.
            sut.onPlayToggled(true)
            sut.onPlayToggled(false)
            XCTAssertEqual(playValues, [true, false], "onPlayToggled should receive toggled values in order.")
        }

        func test_viewComposesWithoutCrash() {
            // Smoke test: ensure the view can be created and rendered to a hosting controller without crashing.
            let selection = SelectionManager()
            var playValues: [Bool] = []

            let sut = ToolbarView(
                selectionManager: selection,
                onSave: {},
                onLoad: {},
                onClear: {},
                onPlayToggled: { playValues.append($0) },
                dirLightCreate: {},
                pointLightCreate: {},
                spotLightCreate: {},
                areaLightCreate: {}
            )

            // Wrap in a hosting controller to ensure SwiftUI can build the body.
            let host = NSHostingController(rootView: sut)
            XCTAssertNotNil(host.view, "Hosting controller should create a view.")
            _ = host // keep alive
            _ = playValues // keep referenced to avoid 'never read' warning
        }
    }
#endif
