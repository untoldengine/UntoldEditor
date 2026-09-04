//
//  GaussianCookSheetTests.swift
//  UntoldEditorTests
//
//  The "Cook to .untoldgs" path: settings → engine cook options, the bake beside the
//  source .ply, and progressive tier detection for placement.
//

import simd
@testable import UntoldEditor
import UntoldEngine
import XCTest

final class GaussianCookSheetTests: XCTestCase {
    private var temporaryDirectory: URL?

    override func tearDown() {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        super.tearDown()
    }

    func test_settingsMapToEngineCookOptions() {
        var settings = GaussianCookSettings()
        settings.chunkSplats = 4096
        settings.shDegree = 2
        settings.flipYZ = true
        settings.scale = 0.5
        settings.minimumOpacity = 0.01

        let options = settings.cookOptions
        XCTAssertEqual(options.log2ChunkSplats, 12)
        XCTAssertEqual(options.shDegree, 2)
        XCTAssertEqual(options.minimumOpacity, 0.01)
        // Scale 0.5 with the Y/Z flip: diagonal (0.5, -0.5, -0.5).
        XCTAssertEqual(options.transform.columns.0.x, 0.5)
        XCTAssertEqual(options.transform.columns.1.y, -0.5)
        XCTAssertEqual(options.transform.columns.2.z, -0.5)

        XCTAssertNil(GaussianCookSettings().shDegree)
        XCTAssertEqual(GaussianCookSettings().cookOptions.log2ChunkSplats, 10)
    }

    func test_cookWritesTiersBesideTheSource() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GaussianCookSheetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let plyURL = directory.appendingPathComponent("chair.ply")
        try makeTestPLY(splatCount: 200).write(to: plyURL)

        var settings = GaussianCookSettings()
        settings.levelCount = 2
        let result = try cookGaussianPLY(plyURL: plyURL, settings: settings)

        XCTAssertEqual(result.tiers.count, 2)
        XCTAssertEqual(result.tiers.map(\.url.lastPathComponent), ["chair_lod0.untoldgs", "chair_lod1.untoldgs"])
        XCTAssertEqual(result.cookReport.inputSplatCount, 200)
        for tier in result.tiers {
            XCTAssertTrue(FileManager.default.fileExists(atPath: tier.url.path))
            XCTAssertNoThrow(try UntoldGSFormat.readHeader(from: tier.url))
        }

        let tiers = try XCTUnwrap(progressiveGaussianTiers(for: result.tiers[1].url))
        XCTAssertEqual(tiers.levelCount, 2)
        XCTAssertEqual(tiers.baseURL.lastPathComponent, "chair")
        XCTAssertEqual(defaultGaussianLODDistances(levelCount: 2), [5, .greatestFiniteMagnitude])

        // A single-tier cook writes one file and is not progressive.
        settings.levelCount = 1
        let single = try cookGaussianPLY(plyURL: plyURL, settings: settings)
        XCTAssertEqual(single.tiers.map(\.url.lastPathComponent), ["chair.untoldgs"])
        XCTAssertNil(progressiveGaussianTiers(for: single.tiers[0].url))
    }

    private func makeTestPLY(splatCount: Int) -> Data {
        var body = ""
        for index in 0 ..< splatCount {
            let x = Float(index % 10) * 0.1
            let y = Float(index / 10 % 10) * 0.1
            let z = Float(index / 100) * 0.1
            body += "\(x) \(y) \(z) 0 0 1 0.2 0.1 -0.1 2.0 -4 -4 -4 1 0 0 0\n"
        }
        let header = """
        ply
        format ascii 1.0
        element vertex \(splatCount)
        property float x
        property float y
        property float z
        property float nx
        property float ny
        property float nz
        property float f_dc_0
        property float f_dc_1
        property float f_dc_2
        property float opacity
        property float scale_0
        property float scale_1
        property float scale_2
        property float rot_0
        property float rot_1
        property float rot_2
        property float rot_3
        end_header

        """
        return Data((header + body).utf8)
    }
}
