//
//  BuildEditModeGraphTests.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class BuildEditModeGraphTests: XCTestCase {
    private func assertNoCycles(_ graph: [String: RenderPass], file: StaticString = #file, line: UInt = #line) {
        enum Mark { case temp, perm }
        var marks: [String: Mark] = [:]

        func dfs(_ node: String) -> Bool {
            if marks[node] == .temp { return false } // cycle
            if marks[node] == .perm { return true } // already ok
            marks[node] = .temp
            for dep in graph[node]?.dependencies ?? [] {
                guard dfs(dep) else { return false }
            }
            marks[node] = .perm
            return true
        }

        for id in graph.keys {
            XCTAssertTrue(dfs(id), "Cycle detected involving \(id)", file: file, line: line)
        }
    }

    private func assertDeps(
        _ graph: [String: RenderPass],
        _ id: String,
        _ expected: [String],
        file: StaticString = #file, line: UInt = #line
    ) {
        let got = graph[id]?.dependencies ?? []
        XCTAssertEqual(
            Set(got), Set(expected),
            "Dependencies for \(id) differ. got=\(got) expected=\(expected)",
            file: file, line: line
        )
    }

    // MARK: - Tests

    func test_buildEditModeGraph_withEnvironmentRoot_fxaaDisabled() {
        let originalEnv = renderEnvironment
        renderEnvironment = true
        defer { renderEnvironment = originalEnv }

        let originalFXAA = FXAAParams.shared.enabled
        FXAAParams.shared.enabled = false
        defer { FXAAParams.shared.enabled = originalFXAA }

        let (graph, finalID) = buildEditModeGraph()

        XCTAssertEqual(finalID, "outputTransform")

        let expectedIDs: Set = [
            "environment", "shadow", "batchedShadow", "model", "batchedModel", "lightPass",
            "transparency", "outline", "lightVisualPass", "gizmo", "precomp", "gaussian", "look", "outputTransform",
        ]
        XCTAssertEqual(Set(graph.keys), expectedIDs)

        assertDeps(graph, "environment", [])
        assertDeps(graph, "shadow", ["environment"])
        assertDeps(graph, "batchedShadow", ["shadow"])
        assertDeps(graph, "model", ["batchedShadow"])
        assertDeps(graph, "batchedModel", ["model"])
        assertDeps(graph, "lightPass", ["batchedModel", "model", "shadow"])
        assertDeps(graph, "transparency", ["lightPass"])
        assertDeps(graph, "outline", ["batchedModel"])
        assertDeps(graph, "lightVisualPass", ["outline"])
        assertDeps(graph, "gizmo", ["lightVisualPass"])
        assertDeps(graph, "gaussian", ["model"])
        assertDeps(graph, "precomp", ["model", "gizmo", "transparency", "gaussian"])
        assertDeps(graph, "look", ["precomp"])
        assertDeps(graph, "outputTransform", ["look"])

        assertNoCycles(graph)
    }

    func test_buildEditModeGraph_withEnvironmentRoot_fxaaEnabled() {
        let originalEnv = renderEnvironment
        renderEnvironment = true
        defer { renderEnvironment = originalEnv }

        let originalFXAA = FXAAParams.shared.enabled
        FXAAParams.shared.enabled = true
        defer { FXAAParams.shared.enabled = originalFXAA }

        let (graph, finalID) = buildEditModeGraph()

        XCTAssertEqual(finalID, "outputTransform")

        let expectedIDs: Set = [
            "environment", "shadow", "batchedShadow", "model", "batchedModel", "lightPass",
            "transparency", "outline", "lightVisualPass", "gizmo", "precomp", "gaussian", "look", "fxaa", "outputTransform",
        ]
        XCTAssertEqual(Set(graph.keys), expectedIDs)

        assertDeps(graph, "environment", [])
        assertDeps(graph, "shadow", ["environment"])
        assertDeps(graph, "batchedShadow", ["shadow"])
        assertDeps(graph, "model", ["batchedShadow"])
        assertDeps(graph, "batchedModel", ["model"])
        assertDeps(graph, "lightPass", ["batchedModel", "model", "shadow"])
        assertDeps(graph, "transparency", ["lightPass"])
        assertDeps(graph, "outline", ["batchedModel"])
        assertDeps(graph, "lightVisualPass", ["outline"])
        assertDeps(graph, "gizmo", ["lightVisualPass"])
        assertDeps(graph, "gaussian", ["model"])
        assertDeps(graph, "precomp", ["model", "gizmo", "transparency", "gaussian"])
        assertDeps(graph, "look", ["precomp"])
        assertDeps(graph, "fxaa", ["look"])
        assertDeps(graph, "outputTransform", ["fxaa"])

        assertNoCycles(graph)
    }

    func test_buildEditModeGraph_withGridRoot_fxaaDisabled() {
        let originalEnv = renderEnvironment
        renderEnvironment = false
        defer { renderEnvironment = originalEnv }

        let originalFXAA = FXAAParams.shared.enabled
        FXAAParams.shared.enabled = false
        defer { FXAAParams.shared.enabled = originalFXAA }

        let (graph, finalID) = buildEditModeGraph()

        XCTAssertEqual(finalID, "outputTransform")

        let expectedIDs: Set = [
            "grid", "shadow", "batchedShadow", "model", "batchedModel", "lightPass",
            "transparency", "outline", "lightVisualPass", "gizmo", "precomp", "gaussian", "look", "outputTransform",
        ]
        XCTAssertEqual(Set(graph.keys), expectedIDs)

        assertDeps(graph, "grid", [])
        assertDeps(graph, "shadow", ["grid"])
        assertDeps(graph, "batchedShadow", ["shadow"])
        assertDeps(graph, "model", ["batchedShadow"])
        assertDeps(graph, "batchedModel", ["model"])
        assertDeps(graph, "lightPass", ["batchedModel", "model", "shadow"])
        assertDeps(graph, "transparency", ["lightPass"])
        assertDeps(graph, "outline", ["batchedModel"])
        assertDeps(graph, "lightVisualPass", ["outline"])
        assertDeps(graph, "gizmo", ["lightVisualPass"])
        assertDeps(graph, "gaussian", ["model"])
        assertDeps(graph, "precomp", ["model", "gizmo", "transparency", "gaussian"])
        assertDeps(graph, "look", ["precomp"])
        assertDeps(graph, "outputTransform", ["look"])

        assertNoCycles(graph)
    }

    func test_buildEditModeGraph_withGridRoot_fxaaEnabled() {
        let originalEnv = renderEnvironment
        renderEnvironment = false
        defer { renderEnvironment = originalEnv }

        let originalFXAA = FXAAParams.shared.enabled
        FXAAParams.shared.enabled = true
        defer { FXAAParams.shared.enabled = originalFXAA }

        let (graph, finalID) = buildEditModeGraph()

        XCTAssertEqual(finalID, "outputTransform")

        let expectedIDs: Set = [
            "grid", "shadow", "batchedShadow", "model", "batchedModel", "lightPass",
            "transparency", "outline", "lightVisualPass", "gizmo", "precomp", "gaussian", "look", "fxaa", "outputTransform",
        ]
        XCTAssertEqual(Set(graph.keys), expectedIDs)

        assertDeps(graph, "grid", [])
        assertDeps(graph, "shadow", ["grid"])
        assertDeps(graph, "batchedShadow", ["shadow"])
        assertDeps(graph, "model", ["batchedShadow"])
        assertDeps(graph, "batchedModel", ["model"])
        assertDeps(graph, "lightPass", ["batchedModel", "model", "shadow"])
        assertDeps(graph, "transparency", ["lightPass"])
        assertDeps(graph, "outline", ["batchedModel"])
        assertDeps(graph, "lightVisualPass", ["outline"])
        assertDeps(graph, "gizmo", ["lightVisualPass"])
        assertDeps(graph, "gaussian", ["model"])
        assertDeps(graph, "precomp", ["model", "gizmo", "transparency", "gaussian"])
        assertDeps(graph, "look", ["precomp"])
        assertDeps(graph, "fxaa", ["look"])
        assertDeps(graph, "outputTransform", ["fxaa"])

        assertNoCycles(graph)
    }
}
