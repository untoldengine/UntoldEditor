//
//  SpatialDebugMenuTests.swift
//  UntoldEditorTests
//

@testable import UntoldEditor
import UntoldEngine
import XCTest

final class SpatialDebugMenuTests: XCTestCase {
    private var savedShowOctreeLeafBounds = false
    private var savedMaxLeafNodeCount = 2000
    private var savedOctreeLeafOccupiedOnly = true
    private var savedOctreeLeafColorMode: SpatialDebugLeafColorMode = .plain
    private var savedColorRenderablesByLOD = false
    private var savedColorRenderablesByStreamingTier = false
    private var savedShowTileBounds = false
    private var savedMaxTileNodeCount = 500
    private var savedShowStaticBatchCellBounds = false
    private var savedMaxStaticBatchCellCount = 2000
    private var savedStaticBatchCellColorMode: SpatialDebugBatchCellColorMode = .plain

    override func setUp() {
        super.setUp()
        let debug = SpatialDebugVisualization.shared
        savedShowOctreeLeafBounds = debug.showOctreeLeafBounds
        savedMaxLeafNodeCount = debug.maxLeafNodeCount
        savedOctreeLeafOccupiedOnly = debug.octreeLeafOccupiedOnly
        savedOctreeLeafColorMode = debug.octreeLeafColorMode
        savedColorRenderablesByLOD = debug.colorRenderablesByLOD
        savedColorRenderablesByStreamingTier = debug.colorRenderablesByStreamingTier
        savedShowTileBounds = debug.showTileBounds
        savedMaxTileNodeCount = debug.maxTileNodeCount
        savedShowStaticBatchCellBounds = debug.showStaticBatchCellBounds
        savedMaxStaticBatchCellCount = debug.maxStaticBatchCellCount
        savedStaticBatchCellColorMode = debug.staticBatchCellColorMode
    }

    override func tearDown() {
        // Restored through the public per-field setters (not the `configure*` functions),
        // so restoring one field never clobbers another back to its engine default.
        let debug = SpatialDebugVisualization.shared
        debug.showOctreeLeafBounds = savedShowOctreeLeafBounds
        debug.maxLeafNodeCount = savedMaxLeafNodeCount
        debug.octreeLeafOccupiedOnly = savedOctreeLeafOccupiedOnly
        debug.octreeLeafColorMode = savedOctreeLeafColorMode
        debug.colorRenderablesByLOD = savedColorRenderablesByLOD
        debug.colorRenderablesByStreamingTier = savedColorRenderablesByStreamingTier
        debug.showTileBounds = savedShowTileBounds
        debug.maxTileNodeCount = savedMaxTileNodeCount
        debug.showStaticBatchCellBounds = savedShowStaticBatchCellBounds
        debug.maxStaticBatchCellCount = savedMaxStaticBatchCellCount
        debug.staticBatchCellColorMode = savedStaticBatchCellColorMode
        super.tearDown()
    }

    func testEveryOptionRoundTripsThroughIsEnabled() {
        for option in SpatialDebugOption.allCases {
            option.isEnabled = true
            XCTAssertTrue(option.isEnabled, "\(option) should read back enabled after being set")
            option.isEnabled = false
            XCTAssertFalse(option.isEnabled, "\(option) should read back disabled after being cleared")
        }
    }

    func testTogglingOctreeLeafBoundsPreservesOccupiedOnlyAndColorMode() {
        SpatialDebugOption.octreeLeafOccupiedOnly.isEnabled = false
        SpatialDebugLeafColorModeOption.current = .residency

        SpatialDebugOption.octreeLeafBounds.isEnabled = true
        XCTAssertFalse(SpatialDebugOption.octreeLeafOccupiedOnly.isEnabled)
        XCTAssertEqual(SpatialDebugLeafColorModeOption.current, .residency)

        SpatialDebugOption.octreeLeafBounds.isEnabled = false
        XCTAssertFalse(
            SpatialDebugOption.octreeLeafOccupiedOnly.isEnabled,
            "disabling the overlay should not reset Occupied Only to the engine default"
        )
        XCTAssertEqual(
            SpatialDebugLeafColorModeOption.current, .residency,
            "disabling the overlay should not reset the leaf color mode to the engine default"
        )
    }

    func testTogglingStaticBatchCellBoundsPreservesColorMode() {
        SpatialDebugBatchCellColorModeOption.current = .lod
        SpatialDebugOption.staticBatchCellBounds.isEnabled = true
        XCTAssertEqual(SpatialDebugBatchCellColorModeOption.current, .lod)
        SpatialDebugOption.staticBatchCellBounds.isEnabled = false
        XCTAssertEqual(
            SpatialDebugBatchCellColorModeOption.current, .lod,
            "disabling the overlay should not reset the cell color mode to the engine default"
        )
    }

    func testLeafColorModeRoundTrips() {
        for mode in SpatialDebugLeafColorModeOption.allCases {
            SpatialDebugLeafColorModeOption.current = mode
            XCTAssertEqual(SpatialDebugVisualization.shared.octreeLeafColorMode, mode.mode)
            XCTAssertEqual(SpatialDebugLeafColorModeOption.current, mode)
        }
    }

    func testBatchCellColorModeRoundTrips() {
        for mode in SpatialDebugBatchCellColorModeOption.allCases {
            SpatialDebugBatchCellColorModeOption.current = mode
            XCTAssertEqual(SpatialDebugVisualization.shared.staticBatchCellColorMode, mode.mode)
            XCTAssertEqual(SpatialDebugBatchCellColorModeOption.current, mode)
        }
    }

    func testGroupsMatchMenuStructure() {
        XCTAssertEqual(SpatialDebugOption.lodLevels.group, .coloring)
        XCTAssertEqual(SpatialDebugOption.textureStreamingTiers.group, .coloring)
        XCTAssertEqual(SpatialDebugOption.octreeLeafBounds.group, .octree)
        XCTAssertEqual(SpatialDebugOption.octreeLeafOccupiedOnly.group, .octree)
        XCTAssertEqual(SpatialDebugOption.tileBounds.group, .tiles)
        XCTAssertEqual(SpatialDebugOption.staticBatchCellBounds.group, .batching)
    }
}
