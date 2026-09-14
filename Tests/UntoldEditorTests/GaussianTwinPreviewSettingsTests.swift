//
//  GaussianTwinPreviewSettingsTests.swift
//  UntoldEditorTests
//
//  The View > Preview Splat Twins toggle: on by default, remembered across launches, and the
//  install / uninstall / re-adoption calls it makes on the twin system.
//

import Foundation
@testable import UntoldEditor
import XCTest

final class GaussianTwinPreviewSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var installs = 0
    private var uninstalls = 0
    private var resets = 0

    override func setUp() {
        super.setUp()
        suiteName = "GaussianTwinPreviewSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        installs = 0
        uninstalls = 0
        resets = 0
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeSettings() -> GaussianTwinPreviewSettings {
        GaussianTwinPreviewSettings(
            defaults: defaults,
            installer: .init(
                install: { [unowned self] in installs += 1 },
                uninstall: { [unowned self] in uninstalls += 1 },
                resetAdoption: { [unowned self] in resets += 1 }
            )
        )
    }

    func test_defaultsToOn_andOnlyTouchesTheEngineOnceActivated() {
        let settings = makeSettings()
        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.isActivated)
        XCTAssertEqual(installs, 0, "no engine before the renderer exists")

        settings.activate()
        XCTAssertTrue(settings.isActivated)
        XCTAssertEqual(installs, 1)
        XCTAssertEqual(resets, 1, "adoption starts fresh on install")
        XCTAssertEqual(uninstalls, 0)
    }

    func test_toggle_installsAndUninstalls_andPersists() {
        let settings = makeSettings()
        settings.activate()

        settings.isEnabled = false
        XCTAssertEqual(uninstalls, 1)
        XCTAssertEqual(defaults.bool(forKey: GaussianTwinPreviewSettings.isEnabledDefaultsKey), false)

        settings.isEnabled = true
        XCTAssertEqual(installs, 2)
        XCTAssertEqual(resets, 2, "links examined while the preview was off are adopted again")

        settings.isEnabled = false
        let relaunched = makeSettings()
        XCTAssertFalse(relaunched.isEnabled, "the preference survives a relaunch")
        relaunched.activate()
        XCTAssertEqual(installs, 2, "off stays off: nothing installed")
        XCTAssertEqual(uninstalls, 3)
    }

    func test_toggleBeforeActivation_onlyRecordsThePreference() {
        let settings = makeSettings()
        settings.isEnabled = false
        settings.isEnabled = true
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(uninstalls, 0)
        XCTAssertTrue(defaults.bool(forKey: GaussianTwinPreviewSettings.isEnabledDefaultsKey))
    }

    func test_sceneDidReset_forgetsAdoptedLinks() {
        let settings = makeSettings()
        settings.activate()
        settings.sceneDidReset()
        settings.sceneDidReset()
        XCTAssertEqual(resets, 3)
    }
}
