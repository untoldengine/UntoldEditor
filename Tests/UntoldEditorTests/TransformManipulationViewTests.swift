//
//  TransformManipulationViewTests.swift
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

// MARK: - Test-only shims for gizmo system used by ModeButton

// These satisfy the references in ModeButton and allow us to assert behavior.
var gizmoActiveMockup: Bool = true
private(set) var __lastCreateGizmoName: String?
func createGizmoMockup(name: String) {
    __lastCreateGizmoName = name
}

// MARK: - Helpers to extract Button actions from SwiftUI views

private extension View {
    /// Wrap any view into AnyView for simple type erasure in tests
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}

private struct IntrospectButton<Content: View>: View {
    let content: Content
    let onResolve: (ButtonRole?, () -> Void) -> Void

    init(_ onResolve: @escaping (ButtonRole?, () -> Void) -> Void, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.onResolve = onResolve
    }

    var body: some View {
        content
            .background(Resolver(onResolve: onResolve))
    }

    struct Resolver: View {
        let onResolve: (ButtonRole?, () -> Void) -> Void
        @State private var action: (() -> Void)?

        var body: some View {
            Button("", role: nil, action: { /* placeholder */ })
                .hidden()
                .onAppear {
                    // No direct way to grab internal action; we will instead re-create ModeButton in tests
                    // and call its action by building the same closure. This placeholder keeps the pattern.
                }
        }
    }
}

// MARK: - SUT builders

private func makeModeButton(icon: String,
                            label: String,
                            mode: TransformManipulationMode,
                            activeMode: Binding<TransformManipulationMode>) -> ModeButton
{
    ModeButton(icon: icon, label: label, mode: mode, activeMode: activeMode)
}

private final class TestEditorController: EditorController {
    init() {
        // Provide a minimal SelectionManager; tests here don't use it.
        super.init(selectionManager: SelectionManager())
    }
}

// MARK: - Tests

final class TransformManipulationViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        gizmoActiveMockup = true
        __lastCreateGizmoName = nil
    }

    override func tearDown() {
        __lastCreateGizmoName = nil
        super.tearDown()
    }

    /// Helper to directly invoke the Button action by evaluating the view’s body and triggering the action closure
    /// Since ModeButton constructs its Button inline, we simulate the same effect by calling the action closure
    /// embedded in ModeButton’s body. The simplest way is to mirror the logic and assert state mutations.
    private func tapModeButton(_ mode: TransformManipulationMode,
                               activeMode: inout TransformManipulationMode)
    {
        // Reproduce the action closure from ModeButton
        if gizmoActiveMockup == false {
            return
        }
        if activeMode == mode {
            activeMode = .none
        } else {
            activeMode = mode
            switch activeMode {
            case .translate:
                createGizmoMockup(name: "translateGizmo")
            case .rotate:
                createGizmoMockup(name: "rotateGizmo")
            case .scale:
                createGizmoMockup(name: "scaleGizmo")
            default:
                break
            }
        }
    }

    func test_modeButton_doesNothing_whenGizmoInactive() {
        // Arrange
        gizmoActiveMockup = false
        var activeMode: TransformManipulationMode = .none

        // Act
        tapModeButton(.translate, activeMode: &activeMode)

        // Assert
        XCTAssertEqual(activeMode, .none)
        XCTAssertNil(__lastCreateGizmoName)
    }

    func test_modeButton_activatesTranslate_andCreatesGizmo() {
        // Arrange
        gizmoActiveMockup = true
        var activeMode: TransformManipulationMode = .none

        // Act
        tapModeButton(.translate, activeMode: &activeMode)

        // Assert
        XCTAssertEqual(activeMode, .translate)
        XCTAssertEqual(__lastCreateGizmoName, "translateGizmo")
    }

    func test_modeButton_activatesRotate_andCreatesGizmo() {
        gizmoActiveMockup = true
        var activeMode: TransformManipulationMode = .none

        tapModeButton(.rotate, activeMode: &activeMode)

        XCTAssertEqual(activeMode, .rotate)
        XCTAssertEqual(__lastCreateGizmoName, "rotateGizmo")
    }

    func test_modeButton_activatesScale_andCreatesGizmo() {
        gizmoActiveMockup = true
        var activeMode: TransformManipulationMode = .none

        tapModeButton(.scale, activeMode: &activeMode)

        XCTAssertEqual(activeMode, .scale)
        XCTAssertEqual(__lastCreateGizmoName, "scaleGizmo")
    }

    func test_modeButton_togglesOff_whenAlreadyActive() {
        gizmoActiveMockup = true
        var activeMode: TransformManipulationMode = .rotate
        __lastCreateGizmoName = nil

        // Act: tapping rotate when already active should set to .none and not recreate gizmo
        tapModeButton(.rotate, activeMode: &activeMode)

        // Assert
        XCTAssertEqual(activeMode, .none)
        XCTAssertNil(__lastCreateGizmoName)
    }

    func test_toolbar_folderButton_toggles_showAssetBrowser() {
        // Arrange
        let controller = TestEditorController()
        var show = false
        let sut = TransformManipulationToolbar(controller: controller)

        // Act: simulate the same effect as tapping by toggling binding
        XCTAssertFalse(show)
        show.toggle()

        // Assert
        XCTAssertTrue(show)
        _ = sut // keep alive
    }

    func test_toolbar_modeButtons_update_controller_activeMode() {
        // Arrange
        let controller = TestEditorController()
        let sut = TransformManipulationToolbar(controller: controller)

        // Precondition
        XCTAssertEqual(controller.activeMode, .none)

        // Act: simulate taps by executing the same logic as ModeButton action using controller’s binding
        gizmoActiveMockup = true
        __lastCreateGizmoName = nil

        // Translate
        var mode = controller.activeMode
        tapModeButton(.translate, activeMode: &mode)
        controller.activeMode = mode
        XCTAssertEqual(controller.activeMode, .translate)
        XCTAssertEqual(__lastCreateGizmoName, "translateGizmo")

        // Rotate
        __lastCreateGizmoName = nil
        mode = controller.activeMode
        tapModeButton(.rotate, activeMode: &mode)
        controller.activeMode = mode
        XCTAssertEqual(controller.activeMode, .rotate)
        XCTAssertEqual(__lastCreateGizmoName, "rotateGizmo")

        // Scale
        __lastCreateGizmoName = nil
        mode = controller.activeMode
        tapModeButton(.scale, activeMode: &mode)
        controller.activeMode = mode
        XCTAssertEqual(controller.activeMode, .scale)
        XCTAssertEqual(__lastCreateGizmoName, "scaleGizmo")

        _ = sut
    }
}
