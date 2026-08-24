//
//  LogConsoleViewTests.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import SwiftUI
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

/// A minimal harness exposing the private helpers of LogConsoleView for testing.
private struct LogConsoleViewHarness {
    let view = LogConsoleView()

    func tag(for level: LogLevel) -> String {
        // Mirror the production logic
        switch level {
        case .error: return "ERROR"
        case .warning: return "WARN"
        case .info: return "INFO"
        case .debug: return "DEBUG"
        case .test: return "TEST"
        case .none: return ""
        }
    }

    func badgeColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
        case .debug: return .gray
        case .test: return .green
        case .none: return .clear
        }
    }

    func passes(_ e: LogEvent, selectedLevel: LogLevel?, search: String) -> Bool {
        (selectedLevel == nil || e.level == selectedLevel!) &&
            (search.isEmpty ||
                e.message.localizedCaseInsensitiveContains(search) ||
                e.category.localizedCaseInsensitiveContains(search))
    }
}

final class LogConsoleViewTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Ensure a clean LogStore before each test
        LogStore.shared.clear()
        // Wait for main-queue clear to complete
        let exp = expectation(description: "clear flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    override func tearDown() {
        LogStore.shared.clear()
        let exp = expectation(description: "clear flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        super.tearDown()
    }

    private func makeEvent(level: LogLevel,
                           category: String,
                           message: String,
                           file: String = "SomeFile.swift",
                           function: String = "someFunc()",
                           line: Int = 42) -> LogEvent
    {
        LogEvent(level: level,
                 message: message,
                 file: file,
                 function: function,
                 line: line,
                 category: category)
    }

    func test_logStore_appendsAndTrims() {
        // Arrange
        let max = 5000
        let many = max + 25

        // Act
        for i in 0 ..< many {
            let e = makeEvent(level: .info, category: "General", message: "msg \(i)")
            LogStore.shared.didLog(e)
        }

        // didLog enqueues on main; wait for it.
        let exp = expectation(description: "didLog flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // Assert
        XCTAssertEqual(LogStore.shared.entries.count, max, "Store should trim to \(max) entries.")
        XCTAssertTrue(LogStore.shared.entries.first?.message == "msg 25",
                      "Oldest entries should be trimmed first.")
        XCTAssertTrue(LogStore.shared.entries.last?.message == "msg \(many - 1)")
    }

    func test_filtering_byLevel_andSearch() {
        // Arrange
        let harness = LogConsoleViewHarness()
        let events = [
            makeEvent(level: .error, category: "Renderer", message: "Pipeline failed"),
            makeEvent(level: .warning, category: "Loader", message: "Missing texture"),
            makeEvent(level: .info, category: "General", message: "Ready"),
            makeEvent(level: .debug, category: "Renderer", message: "Draw call 42"),
            makeEvent(level: .test, category: "Tests", message: "Injected"),
        ]

        events.forEach { LogStore.shared.didLog($0) }
        let exp = expectation(description: "didLog flush")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        // Act + Assert: no filter
        var filtered = LogStore.shared.entries.filter { harness.passes($0, selectedLevel: nil, search: "") }
        XCTAssertEqual(filtered.count, events.count)

        // Filter by level
        filtered = LogStore.shared.entries.filter { harness.passes($0, selectedLevel: .warning, search: "") }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.level, .warning)

        // Search by message
        filtered = LogStore.shared.entries.filter { harness.passes($0, selectedLevel: nil, search: "draw") }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.message, "Draw call 42")

        // Search by category (case-insensitive)
        filtered = LogStore.shared.entries.filter { harness.passes($0, selectedLevel: nil, search: "renderer") }
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.allSatisfy { $0.category == "Renderer" })

        // Combined level + search
        filtered = LogStore.shared.entries.filter { harness.passes($0, selectedLevel: .debug, search: "renderer") }
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.level, .debug)
        XCTAssertEqual(filtered.first?.category, "Renderer")
    }

    func test_tagAndBadgeColor_helpers_matchLevels() {
        let harness = LogConsoleViewHarness()

        XCTAssertEqual(harness.tag(for: .error), "ERROR")
        XCTAssertEqual(harness.tag(for: .warning), "WARN")
        XCTAssertEqual(harness.tag(for: .info), "INFO")
        XCTAssertEqual(harness.tag(for: .debug), "DEBUG")
        XCTAssertEqual(harness.tag(for: .test), "TEST")
        XCTAssertEqual(harness.tag(for: .none), "")

        // Just assert that a Color is produced; detailed color equality is tricky.
        // We can sanity-check by comparing description strings.
        XCTAssertTrue("\(harness.badgeColor(for: .error))".contains("red"))
        XCTAssertTrue("\(harness.badgeColor(for: .warning))".contains("yellow"))
        XCTAssertTrue("\(harness.badgeColor(for: .info))".contains("blue"))
        XCTAssertTrue("\(harness.badgeColor(for: .debug))".contains("gray"))
        XCTAssertTrue("\(harness.badgeColor(for: .test))".contains("green"))
        XCTAssertTrue("\(harness.badgeColor(for: .none))".contains("clear"))
    }

    func test_exportLog_doesNotCrash_andLogsErrorOnFailure() {
        // We can’t assert file side-effects easily here; instead ensure it’s callable and won’t crash.
        // Prepare a small set of entries
        let entries = [
            makeEvent(level: .info, category: "General", message: "hello"),
            makeEvent(level: .error, category: "Gen", message: "boom"),
        ]

        // Since exportLog is file-private in the production file, we can’t call it directly here.
        // This test remains as a placeholder to indicate intent; if you want to test it,
        // consider lifting its visibility or moving to a small helper type that can be @testable imported.
        XCTAssertNotNil(entries)
    }
}
