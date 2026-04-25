//
//  LightDebugMeshTest.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.

// These unit tests were jump-started with AI assistance — then refined by humans. If you spot an issue, please submit an issue.

import ModelIO
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class LightDebugMeshesTests: XCTestCase {
    private var originalSpot: [Mesh]?
    private var originalPoint: [Mesh]?
    private var originalArea: [Mesh]?
    private var originalDir: [Mesh]?

    override func setUp() {
        super.setUp()

        guard let device = MTLCreateSystemDefaultDevice() else {
            assertionFailure("Metal device is not available.")
            return
        }

        renderInfo.device = device
        vertexDescriptor.model = MDLVertexDescriptor()
    }

    override func tearDown() {
        super.tearDown()
    }

    func test_loadLightDebugMeshes_assignsAllMeshes() {
        loadLightDebugMeshes()

        XCTAssertNotNil(spotLightDebugMesh, "spotLightDebugMesh should be loaded.")
        XCTAssertNotNil(pointLightDebugMesh, "pointLightDebugMesh should be loaded.")
        XCTAssertNotNil(areaLightDebugMesh, "areaLightDebugMesh should be loaded.")
        XCTAssertNotNil(dirLightDebugMesh, "dirLightDebugMesh should be loaded.")
    }

    func test_loadLightDebugMeshes_loadsCorrectNames() {
        loadLightDebugMeshes()

        XCTAssertEqual(spotLightDebugMesh.first?.assetName, "Cone")
        XCTAssertEqual(pointLightDebugMesh.first?.assetName, "Sphere")
        XCTAssertEqual(areaLightDebugMesh.first?.assetName, "Plane")
        XCTAssertEqual(dirLightDebugMesh.first?.assetName, "Sphere")
    }
}
