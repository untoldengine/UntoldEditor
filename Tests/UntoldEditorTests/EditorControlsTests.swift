//
//  EditorControlsTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
@testable import UntoldEditor
import XCTest

/// The state logic of the shared controls, kept as static functions so it can be
/// checked without rendering: which color a state takes, what a drag reports.
final class EditorControlsTests: XCTestCase {
    // MARK: - EditorPillButton

    func test_pillButton_disabledGlyphWinsOverActive() {
        XCTAssertEqual(EditorPillButton.glyphColor(isActive: true, isEnabled: false), .editorTextDisabled)
        XCTAssertEqual(EditorPillButton.glyphColor(isActive: false, isEnabled: false), .editorTextDisabled)
    }

    func test_pillButton_activeGlyphIsInverseOnTheAccent() {
        XCTAssertEqual(EditorPillButton.glyphColor(isActive: true, isEnabled: true), .editorTextInverse)
        XCTAssertEqual(EditorPillButton.glyphColor(isActive: false, isEnabled: true), .editorTextPrimary)
    }

    // MARK: - EditorPopupMenuRow

    func test_popupMenuRow_checkedRowReadsInverse() {
        XCTAssertEqual(EditorPopupMenuRow.textColor(isChecked: true), .editorTextInverse)
        XCTAssertEqual(EditorPopupMenuRow.textColor(isChecked: false), .editorTextPrimary)
        XCTAssertEqual(EditorPopupMenuRow.detailColor(isChecked: false), .editorTextTertiary)
        XCTAssertNotEqual(EditorPopupMenuRow.detailColor(isChecked: true), .editorTextTertiary)
    }

    // MARK: - EditorFilterChip

    func test_filterChip_activeLabelIsPrimary_inactiveKeepsItsTint() {
        XCTAssertEqual(EditorFilterChip.labelColor(isActive: true, tint: .editorError), .editorTextPrimary)
        XCTAssertEqual(EditorFilterChip.labelColor(isActive: false, tint: .editorError), .editorError)
    }

    // MARK: - EditorSplitDivider

    func test_splitDivider_verticalLineReportsHorizontalMovement() {
        let drag = CGSize(width: 12, height: -3)
        XCTAssertEqual(EditorSplitDivider.translation(of: drag, along: .vertical), 12)
        XCTAssertEqual(EditorSplitDivider.translation(of: drag, along: .horizontal), -3)
    }

    // MARK: - EditorType

    func test_typeScale_definesTheSpecSizes() {
        // Fonts have no public size accessor; building each one proves the scale
        // exists and resolves, which is what a view needs.
        let fonts: [Font] = [EditorType.body, EditorType.title, EditorType.toolbar, EditorType.hint, EditorType.badge, EditorType.mono, EditorType.monoSmall]
        XCTAssertEqual(fonts.count, 7)
        XCTAssertEqual(EditorType.Radius.field, 6)
        XCTAssertEqual(EditorType.Radius.pill, 7)
        XCTAssertEqual(EditorType.Radius.button, 5)
        XCTAssertEqual(EditorType.Radius.card, 8)
    }
}
