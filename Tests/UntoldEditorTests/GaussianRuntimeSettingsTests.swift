//
//  GaussianRuntimeSettingsTests.swift
//  UntoldEditorTests
//
//  View > Splat Debug > Working Set: the editor's frame-time budget for splats, persisted per
//  user and installed as the engine's working-set override once the editor renders.
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

final class GaussianRuntimeSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var savedOverride: Int?

    override func setUp() {
        super.setUp()
        savedOverride = GaussianRuntimeLimits.workingSetSplatsOverride
        suiteName = "GaussianRuntimeSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        GaussianRuntimeLimits.workingSetSplatsOverride = savedOverride
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func test_defaultsToThreeMillionAndPersists() {
        let settings = EditorGaussianRuntimeSettings(defaults: defaults)
        XCTAssertEqual(settings.workingSet, .threeMillion, "the editor's default, about 30 ms per 1080p frame on an M4 Max")
        XCTAssertEqual(EditorSplatWorkingSet.editorDefault, .threeMillion)

        settings.workingSet = .oneMillion
        XCTAssertEqual(defaults.string(forKey: EditorGaussianRuntimeSettings.workingSetDefaultsKey), "oneMillion")
        XCTAssertEqual(EditorGaussianRuntimeSettings(defaults: defaults).workingSet, .oneMillion, "a new instance reads the saved choice")

        defaults.set("not a choice", forKey: EditorGaussianRuntimeSettings.workingSetDefaultsKey)
        XCTAssertEqual(EditorGaussianRuntimeSettings(defaults: defaults).workingSet, .threeMillion, "an unknown value falls back to the default")
    }

    func test_installsTheEngineOverrideOnlyOnceActivated() {
        GaussianRuntimeLimits.workingSetSplatsOverride = nil
        let settings = EditorGaussianRuntimeSettings(defaults: defaults)
        settings.workingSet = .twoMillion
        XCTAssertNil(GaussianRuntimeLimits.workingSetSplatsOverride, "before activation the choice is only recorded")

        settings.activate()
        XCTAssertEqual(GaussianRuntimeLimits.workingSetSplatsOverride, 2_000_000)
        settings.workingSet = .fourMillion
        XCTAssertEqual(GaussianRuntimeLimits.workingSetSplatsOverride, 4_000_000, "a change while active applies at once")
        settings.workingSet = .engineDefault
        XCTAssertNil(GaussianRuntimeLimits.workingSetSplatsOverride, "the engine default clears the override")
        settings.workingSet = .threeMillion
        XCTAssertEqual(GaussianRuntimeLimits.workingSetSplatsOverride, 3_000_000)

        settings.deactivate()
        XCTAssertNil(GaussianRuntimeLimits.workingSetSplatsOverride)
        XCTAssertFalse(settings.isActivated)
    }

    func test_choicesNameTheirSizeAndCost() {
        let titles = EditorSplatWorkingSet.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "every menu item has its own title")
        XCTAssertEqual(EditorSplatWorkingSet.threeMillion.title, "3,000,000 (Editor Default)")
        XCTAssertEqual(EditorSplatWorkingSet.oneMillion.title, "1,000,000")
        XCTAssertEqual(EditorSplatWorkingSet.engineDefault.title, "Engine Default (\(GaussianSplatBudget.formatted(GaussianRuntimeLimits.workingSetSplats)))")
        XCTAssertEqual(EditorSplatWorkingSet.engineDefault.splatsInEffect, GaussianRuntimeLimits.workingSetSplats)
        XCTAssertNil(EditorSplatWorkingSet.engineDefault.splats)
        XCTAssertTrue(EditorSplatWorkingSet.threeMillion.summary.contains("about 33 ms of GPU per 1080p frame"), EditorSplatWorkingSet.threeMillion.summary)
        XCTAssertTrue(EditorSplatWorkingSet.threeMillion.summary.contains("617.98 MiB of working-set buffers"), EditorSplatWorkingSet.threeMillion.summary)
    }
}
