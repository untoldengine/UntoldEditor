//
//  SplatDebugMenuTests.swift
//  UntoldEditorTests
//
//  View > Splat Debug: every engine switch (GaussianDebugOptions) the menu exposes round-trips
//  through its menu option, the level mode through its radio items, and the items are
//  distinct and grouped in menu order.
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

final class SplatDebugMenuTests: XCTestCase {
    private var savedSwitches: [SplatDebugOption: Bool] = [:]
    private var savedLevelMode = GaussianLevelMode.auto
    private var savedThresholdOverride: Int?

    override func setUp() {
        super.setUp()
        for option in SplatDebugOption.allCases {
            savedSwitches[option] = option.isEnabled
        }
        savedLevelMode = GaussianDebugOptions.shared.gaussianLevelMode
        savedThresholdOverride = GaussianPagingPolicy.pagingThresholdBytesOverride
    }

    override func tearDown() {
        for (option, value) in savedSwitches {
            option.isEnabled = value
        }
        GaussianDebugOptions.shared.gaussianLevelMode = savedLevelMode
        GaussianPagingPolicy.pagingThresholdBytesOverride = savedThresholdOverride
        super.tearDown()
    }

    func test_everySwitchRoundTripsToTheEngine() {
        let options = GaussianDebugOptions.shared
        for option in SplatDebugOption.allCases {
            option.isEnabled = true
            XCTAssertTrue(option.isEnabled, option.title)
            option.isEnabled = false
            XCTAssertFalse(option.isEnabled, option.title)
        }
        // Each option drives its own engine switch, not a neighbour's.
        SplatDebugOption.paging.isEnabled = true
        XCTAssertTrue(options.disablePaging)
        XCTAssertFalse(options.freezePaging)
        SplatDebugOption.paging.isEnabled = false
        SplatDebugOption.freezePaging.isEnabled = true
        XCTAssertTrue(options.freezePaging)
        XCTAssertFalse(options.disablePaging)
        SplatDebugOption.freezePaging.isEnabled = false
        SplatDebugOption.forcePaging.isEnabled = true
        XCTAssertFalse(options.disablePaging)
        XCTAssertFalse(options.freezePaging)
        SplatDebugOption.forcePaging.isEnabled = false
        SplatDebugOption.antiAliasSplatPixels.isEnabled = true
        XCTAssertTrue(options.antiAliasSplatPixels)
        SplatDebugOption.antiAliasSplatPixels.isEnabled = false
        XCTAssertFalse(options.antiAliasSplatPixels)
        SplatDebugOption.toneMapSplatPixels.isEnabled = true
        XCTAssertTrue(options.toneMapSplatPixels)
        XCTAssertFalse(options.antiAliasSplatPixels, "its own switch")
        SplatDebugOption.toneMapSplatPixels.isEnabled = false
        XCTAssertFalse(options.toneMapSplatPixels)
        SplatDebugOption.residencyTint.isEnabled = true
        XCTAssertTrue(options.residencyDebugTint)
        SplatDebugOption.residencyTint.isEnabled = false
        SplatDebugOption.levelCrossFade.isEnabled = true
        XCTAssertTrue(options.disableLevelCrossFade)
        XCTAssertFalse(options.levelDebugTint)
        SplatDebugOption.levelCrossFade.isEnabled = false
        SplatDebugOption.levelTint.isEnabled = true
        XCTAssertTrue(options.levelDebugTint)
        SplatDebugOption.levelTint.isEnabled = false
        SplatDebugOption.chunkBounds.isEnabled = true
        XCTAssertTrue(SpatialDebugVisualization.shared.showGaussianChunkBounds)
        XCTAssertEqual(SpatialDebugVisualization.shared.gaussianChunkColorMode, .level)
        SplatDebugOption.chunkBounds.isEnabled = false
        SplatDebugOption.chunkCull.isEnabled = true
        XCTAssertTrue(options.disableChunkCull)
        SplatDebugOption.chunkCull.isEnabled = false
        SplatDebugOption.workingSetBudget.isEnabled = true
        XCTAssertTrue(options.disableWorkingSetBudget)
        SplatDebugOption.workingSetBudget.isEnabled = false
        SplatDebugOption.screenWeightedQuotas.isEnabled = true
        XCTAssertTrue(options.disableScreenWeightedQuotas)
        SplatDebugOption.screenWeightedQuotas.isEnabled = false
    }

    func test_itemsAreDistinctAndGroupedInMenuOrder() {
        let titles = SplatDebugOption.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count, "every item has its own title")
        for option in SplatDebugOption.allCases {
            XCTAssertFalse(option.summary.isEmpty, option.title)
            XCTAssertTrue(option.title.contains("Splat"), option.title)
        }
        let groups = SplatDebugOption.allCases.map(\.group.rawValue)
        XCTAssertEqual(groups, groups.sorted(), "the groups are contiguous in menu order")
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .draw }, [.hzbOcclusionCull, .opaqueDepthTest, .antiAliasSplatPixels, .toneMapSplatPixels, .crispSplatKernel])
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .paging }, [.paging, .forcePaging, .freezePaging, .residencyTint])
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .levels }, [.levelCrossFade, .levelTint])
        XCTAssertEqual(SplatDebugOption.allCases.filter { $0.group == .bounds }, [.chunkBounds])
        XCTAssertEqual(SplatDebugOption.paging.title, "Disable Splat Paging")
        XCTAssertEqual(SplatDebugOption.levelTint.title, "Tint Splats by Level")
        XCTAssertEqual(SplatDebugOption.levelCrossFade.title, "Disable Splat Level Cross-Fade")
    }

    func test_forcePagingZeroesTheEnginePagingThreshold() {
        let budget = 6 << 30
        GaussianPagingPolicy.pagingThresholdBytesOverride = nil
        XCTAssertFalse(SplatDebugOption.forcePaging.isEnabled)
        let platformThreshold = GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: budget)
        XCTAssertGreaterThan(platformThreshold, 0)

        SplatDebugOption.forcePaging.isEnabled = true
        XCTAssertEqual(GaussianPagingPolicy.pagingThresholdBytesOverride, 0)
        XCTAssertEqual(GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: budget), 0)
        // Any chunked asset now pages; the disable switch still wins.
        XCTAssertTrue(GaussianPagingPolicy.shouldPage(assetBytes: 1, thresholdBytes: 0, allowPaging: true, disablePaging: false))
        XCTAssertFalse(GaussianPagingPolicy.shouldPage(assetBytes: 1, thresholdBytes: 0, allowPaging: true, disablePaging: true))
        XCTAssertEqual(SplatDebugOption.forcePaging.title, "Force Splat Paging")

        SplatDebugOption.forcePaging.isEnabled = false
        XCTAssertNil(GaussianPagingPolicy.pagingThresholdBytesOverride)
        XCTAssertEqual(GaussianPagingPolicy.pagingThresholdBytes(residencyBudgetBytes: budget), platformThreshold)

        // An override the engine set to another figure is not this switch.
        GaussianPagingPolicy.pagingThresholdBytesOverride = 64 << 20
        XCTAssertFalse(SplatDebugOption.forcePaging.isEnabled)
        GaussianPagingPolicy.pagingThresholdBytesOverride = nil
    }

    func test_blendCapRoundTripsThroughItsRadioItems() {
        let savedOverride = GaussianRuntimeLimits.maxBlendedSplatsPerPixelOverride
        let savedDisable = GaussianDebugOptions.shared.disableBlendCap
        defer {
            GaussianRuntimeLimits.maxBlendedSplatsPerPixelOverride = savedOverride
            GaussianDebugOptions.shared.disableBlendCap = savedDisable
        }
        XCTAssertEqual(SplatBlendCapOption.allCases.map(\.title), ["64 (Mobile Default)", "128 (Mac Default)", "Unlimited"])
        for choice in SplatBlendCapOption.allCases {
            SplatBlendCapOption.current = choice
            XCTAssertEqual(GaussianRuntimeLimits.maxBlendedSplatsPerPixel, choice.splats, choice.title)
            XCTAssertEqual(SplatBlendCapOption.current, choice)
            XCTAssertFalse(GaussianDebugOptions.shared.disableBlendCap, "a choice replaces the debug lift")
            XCTAssertFalse(choice.summary.isEmpty)
        }
        GaussianRuntimeLimits.maxBlendedSplatsPerPixelOverride = 100
        XCTAssertEqual(SplatBlendCapOption.current, .mac, "an override set by the engine shows as the nearest choice")
        GaussianRuntimeLimits.maxBlendedSplatsPerPixelOverride = 70
        XCTAssertEqual(SplatBlendCapOption.current, .mobile)
    }

    func test_levelModeRoundTripsThroughItsRadioItems() {
        XCTAssertEqual(SplatLevelModeOption.allCases.map(\.title), ["Auto", "Fine Only", "Coarse Only"])
        for mode in SplatLevelModeOption.allCases {
            SplatLevelModeOption.current = mode
            XCTAssertEqual(GaussianDebugOptions.shared.gaussianLevelMode, mode.mode, mode.title)
            XCTAssertEqual(SplatLevelModeOption.current, mode)
            XCTAssertFalse(mode.summary.isEmpty)
        }
        GaussianDebugOptions.shared.gaussianLevelMode = .coarseOnly
        XCTAssertEqual(SplatLevelModeOption.current, .coarseOnly, "a mode set by the engine shows in the menu")
        for mode in GaussianLevelMode.allCases {
            XCTAssertEqual(SplatLevelModeOption(mode: mode).mode, mode)
        }
    }
}
