//
//  ViewportOverlayTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import simd
@testable import UntoldEditor
import XCTest

/// The small parts of the viewport's overlays: the hints, the switches of
/// the View menu, the compact statistics, the mode badge and the drags on the
/// navigation controls.
final class ViewportOverlayTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "ViewportOverlayTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Hints

    func test_theHints_sayHowTheCameraIsSteered() {
        let hints = ViewportHints.hints(style: .classic, hasSelection: false)

        XCTAssertEqual(hints.map(\.action), ["Look", "Fly", "Zoom", "Pan", "Move", "Orbit"])
        XCTAssertEqual(hints.map(\.keys), ["Right drag", "W A S D Q E", "Scroll", "⇧ Right drag", "⌘ Right drag", "⌥ Right drag"])
    }

    func test_theHints_agreeWithWhatTheRightButtonDoes() {
        XCTAssertEqual(EditorNavigationSettings.dragAction(shiftPressed: false, commandPressed: false, optionPressed: false), .look)
        XCTAssertEqual(EditorNavigationSettings.dragAction(shiftPressed: true, commandPressed: false, optionPressed: false), .pan)
        XCTAssertEqual(EditorNavigationSettings.dragAction(shiftPressed: false, commandPressed: true, optionPressed: false), .zoom)
        XCTAssertEqual(EditorNavigationSettings.dragAction(shiftPressed: false, commandPressed: false, optionPressed: true), .orbit)
        XCTAssertTrue(ViewportHints.pan.keys.hasPrefix("⇧"))
        XCTAssertTrue(ViewportHints.move.keys.hasPrefix("⌘"))
        XCTAssertTrue(ViewportHints.orbit.keys.hasPrefix("⌥"))
    }

    func test_framing_isHintedOnlyWithSomethingToFrame() {
        XCTAssertFalse(ViewportHints.hints(style: .classic, hasSelection: false).contains(ViewportHints.frameSelection))
        XCTAssertEqual(ViewportHints.hints(style: .classic, hasSelection: true).first, ViewportHints.frameSelection)
    }

    func test_inTheBlenderStyle_scrollingOrbits_andIsHintedOnce() {
        let hints = ViewportHints.hints(style: .blender, hasSelection: false)

        XCTAssertEqual(hints.map(\.action), ["Look", "Fly", "Orbit", "Pan", "Move"])
        XCTAssertEqual(hints.first { $0.action == "Orbit" }?.keys, "Scroll")
    }

    func test_everyHint_hasItsOwnIdentity() {
        for style in CameraNavigationStyle.allCases {
            let ids = ViewportHints.hints(style: style, hasSelection: true).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, style.title)
        }
    }

    func test_aNarrowViewport_dropsHintsFromTheEnd() {
        XCTAssertEqual(ViewportHintChips.lengths(for: 4), [4, 3, 2, 1])
        XCTAssertEqual(ViewportHintChips.lengths(for: 1), [1])
        XCTAssertEqual(ViewportHintChips.lengths(for: 0), [])
    }

    // MARK: - The switches of the View menu

    func test_everyOverlay_showsAtFirst() {
        let settings = EditorViewportOverlaySettings(defaults: defaults)

        for overlay in ViewportOverlay.allCases {
            XCTAssertTrue(settings.isShown(overlay), overlay.title)
        }
        XCTAssertEqual(settings.storedStatsMode, .simplified)
    }

    func test_anOverlayThatWasHidden_staysHiddenAtTheNextLaunch() {
        let settings = EditorViewportOverlaySettings(defaults: defaults)
        settings.toggle(.navigationGizmo)
        XCTAssertFalse(settings.isShown(.navigationGizmo))

        let next = EditorViewportOverlaySettings(defaults: defaults)

        XCTAssertFalse(next.isShown(.navigationGizmo))
        XCTAssertTrue(next.isShown(.hints))

        next.toggle(.navigationGizmo)
        XCTAssertTrue(EditorViewportOverlaySettings(defaults: defaults).isShown(.navigationGizmo))
    }

    func test_theFormOfTheStatistics_isKept() {
        let settings = EditorViewportOverlaySettings(defaults: defaults)

        settings.storeStatsMode(.off)
        XCTAssertEqual(EditorViewportOverlaySettings(defaults: defaults).storedStatsMode, .off)

        settings.storeStatsMode(.advanced)
        XCTAssertEqual(EditorViewportOverlaySettings(defaults: defaults).storedStatsMode, .advanced)
    }

    func test_withoutDefaults_nothingIsKept() {
        let settings = EditorViewportOverlaySettings(defaults: nil)
        settings.setShown(.hints, false)

        XCTAssertFalse(settings.isShown(.hints))
        XCTAssertTrue(EditorViewportOverlaySettings(defaults: nil).isShown(.hints))
    }

    func test_everyOverlay_hasItsItemInTheMenu() {
        let titles = ViewportOverlay.allCases.map(\.title)

        XCTAssertEqual(titles, ["Mode Badge", "Navigation Gizmo", "Shortcut Hints"])
        XCTAssertTrue(ViewportOverlay.allCases.allSatisfy { $0.summary.isEmpty == false })
    }

    // MARK: - The compact statistics

    func test_theTiming_isTheFrameRateWithTheFramesTime() {
        XCTAssertEqual(EngineStatsCompactText.timing(frameMs: 16.129), "62 fps · 16.1 ms")
        XCTAssertEqual(EngineStatsCompactText.timing(frameMs: 4.2), "238 fps · 4.2 ms")
    }

    func test_withoutAFrame_theTimingIsDashes() {
        XCTAssertEqual(EngineStatsCompactText.timing(frameMs: 0), "— fps · — ms")
        XCTAssertEqual(EngineStatsCompactText.timing(frameMs: .nan), "— fps · — ms")
    }

    func test_whatWasDrawn_groupsTheThousands() {
        XCTAssertEqual(EngineStatsCompactText.drawn(triangles: 1248, drawCalls: 3), "1,248 tris · 3 draw calls")
        XCTAssertEqual(EngineStatsCompactText.drawn(triangles: 2_500_000, drawCalls: 1), "2,500,000 tris · 1 draw call")
        XCTAssertEqual(EngineStatsCompactText.drawn(triangles: 1, drawCalls: 0), "1 tri · 0 draw calls")
    }

    // MARK: - The mode badge

    func test_objectMode_isADarkScrimWithLightText() {
        XCTAssertEqual(ModeBadgeView.background(for: .object), .editorScrim)
        XCTAssertEqual(ModeBadgeView.textColor(for: .object), .editorTextPrimary)
        XCTAssertEqual(InteractionMode.object.title.uppercased(), "OBJECT MODE")
    }

    // MARK: - A drag on a navigation control

    func test_aPressThatHardlyMoves_isAClick() {
        var drag = NavigationDrag(clickSlop: 3)

        XCTAssertNil(drag.step(to: CGSize(width: 2, height: 1)))
        XCTAssertFalse(drag.isDragging)
    }

    func test_aPressThatTravels_isADrag_andItsStepsAddUpToTheTravel() {
        var drag = NavigationDrag(clickSlop: 3)

        let first = drag.step(to: CGSize(width: 10, height: 0))
        let second = drag.step(to: CGSize(width: 14, height: -6))

        XCTAssertTrue(drag.isDragging)
        XCTAssertEqual(first, simd_float2(10, 0))
        // Down the screen is a larger y for the gesture, and a smaller one for the camera.
        XCTAssertEqual(second, simd_float2(4, 6))
    }

    func test_aSlowDrag_isKeptUntilItMakesAStep() {
        var drag = NavigationDrag(clickSlop: 0, minimumStep: 2)

        XCTAssertNil(drag.step(to: CGSize(width: 1, height: 0)))
        XCTAssertNil(drag.step(to: CGSize(width: 1.5, height: 0)))
        XCTAssertEqual(drag.step(to: CGSize(width: 2.5, height: 0)), simd_float2(2.5, 0))
        XCTAssertNil(drag.step(to: CGSize(width: 3, height: 0)))
        XCTAssertEqual(drag.step(to: CGSize(width: 5, height: 0)), simd_float2(2.5, 0))
    }

    func test_aDragThatDoesNotMove_makesNoStep() {
        var drag = NavigationDrag(clickSlop: 0)

        XCTAssertEqual(drag.step(to: CGSize(width: 4, height: 0)), simd_float2(4, 0))
        XCTAssertNil(drag.step(to: CGSize(width: 4, height: 0)))
    }

    func test_theOrbitOfTheGizmo_stepsOverTheOrbitsDeadZone() {
        // The orbit ignores a step of a point or less along its axis.
        XCTAssertGreaterThan(NavigationGizmoView.orbitStep, 1)
    }
}
