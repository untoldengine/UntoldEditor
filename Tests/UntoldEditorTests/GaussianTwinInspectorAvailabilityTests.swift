//
//  GaussianTwinInspectorAvailabilityTests.swift
//  UntoldEditorTests
//
//  Which selections get the Inspector's Splat Twin section. It is an ad-hoc section, so it
//  shows under `EditorAuthoringMode.sceneCompositionOnly` — which hides the Gaussian
//  component editor — for meshes placed from a `.untold` asset and for nothing else.
//

import Foundation
@testable import UntoldEditor
@testable import UntoldEngine
import XCTest

final class GaussianTwinInspectorAvailabilityTests: XCTestCase {
    private var directory: URL!
    private var untold: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        scene = Scene()
        EditorComponentsState.shared.clear()
        directory = try GaussianTwinTestFixtures.makeTemporaryDirectory()
        untold = try GaussianTwinTestFixtures.writeUntold(to: directory)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        EditorComponentsState.shared.clear()
        super.tearDown()
    }

    func test_meshAssetRoot_isAvailableInSceneCompositionMode() {
        XCTAssertTrue(EditorAuthoringMode.sceneCompositionOnly, "the section is gated on its own, not on the component registry")
        let entity = GaussianTwinTestFixtures.makeMeshEntity(assetURL: untold)

        XCTAssertTrue(GaussianTwinInspector.isAvailable(entity))
        // The gate `InspectorView.body` uses is the policy itself, in this mode too.
        XCTAssertTrue(InspectorView.showsGaussianTwinSection(for: entity))
        let light = createEntity()
        registerComponent(entityId: light, componentType: LocalTransformComponent.self)
        registerComponent(entityId: light, componentType: DirectionalLightComponent.self)
        XCTAssertFalse(InspectorView.showsGaussianTwinSection(for: light))
        // The registry-driven Gaussian editor stays hidden; the twin section is the only
        // splat authoring the composition-only inspector offers.
        XCTAssertFalse(canShowComponentInInspector(componentType: GaussianComponent.self, for: entity))
        let merged = mergeEntityComponents(selectedEntity: entity, editor_availableComponents: availableComponents_Editor)
        XCTAssertNil(merged[ObjectIdentifier(GaussianComponent.self)])
    }

    func test_bindableMeshNode_isAvailable_rootAndTransformOnlyNodeAreNot() throws {
        let hierarchy = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "Table", hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: hierarchy, nodePath: GaussianTwinTestFixtures.hierarchyChildNodePath)
        XCTAssertTrue(isBindableAssetMeshNode(placed.node))
        XCTAssertTrue(GaussianTwinInspector.isAvailable(placed.node))
        XCTAssertFalse(GaussianTwinInspector.isAvailable(placed.root), "a multi-node root has no mesh to swap")

        let bare = GaussianTwinTestFixtures.makeAssetInstance(assetURL: hierarchy, nodePath: "Root/root_entity#0/pivot#3", withMesh: false)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(bare.node), "transform-only nodes")
    }

    func test_streamedStub_isNotAvailable() throws {
        // A streamed tile node: RenderComponent + DerivedAssetNodeComponent after upload, but
        // its node path is the streamer's (`Root/<name>#<index>`), not the file's.
        let hierarchy = try GaussianTwinTestFixtures.writeUntold(to: directory, name: "tile_03", hierarchy: true)
        let placed = GaussianTwinTestFixtures.makeAssetInstance(assetURL: hierarchy, nodePath: "Root/wall#2#2")
        XCTAssertTrue(GaussianTwinInspector.isAvailable(placed.node), "before: an ordinary mesh node")
        registerComponent(entityId: placed.node, componentType: StreamingComponent.self)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(placed.node))
        XCTAssertFalse(InspectorView.showsGaussianTwinSection(for: placed.node))
    }

    func test_lightsCamerasPrimitivesAndSplats_areNotAvailable() {
        let light = createEntity()
        registerComponent(entityId: light, componentType: LocalTransformComponent.self)
        registerComponent(entityId: light, componentType: DirectionalLightComponent.self)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(light))

        let litMesh = GaussianTwinTestFixtures.makeMeshEntity(name: "Lamp", assetURL: untold)
        registerComponent(entityId: litMesh, componentType: PointLightComponent.self)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(litMesh), "a light's debug mesh is not a twin candidate")

        let camera = createEntity()
        registerComponent(entityId: camera, componentType: LocalTransformComponent.self)
        registerComponent(entityId: camera, componentType: CameraComponent.self)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(camera))

        let primitive = GaussianTwinTestFixtures.makeMeshEntity(name: "Cube", assetURL: URL(fileURLWithPath: ""))
        XCTAssertFalse(GaussianTwinInspector.isAvailable(primitive), "no .untold behind it")

        let splat = createEntity()
        registerComponent(entityId: splat, componentType: LocalTransformComponent.self)
        registerComponent(entityId: splat, componentType: GaussianComponent.self)
        XCTAssertFalse(GaussianTwinInspector.isAvailable(splat))

        XCTAssertFalse(GaussianTwinInspector.isAvailable(.invalid))
    }

    func test_assignablePayload_isACookedGaussianFromTheBrowser() {
        let cooked = Asset(name: "chair", category: AssetCategory.gaussians.rawValue, path: URL(fileURLWithPath: "/GameData/Gaussians/chair.untoldgs"))
        XCTAssertEqual(GaussianTwinInspector.assignablePayloadURL(from: cooked), cooked.path)

        let upperCase = Asset(name: "chair", category: AssetCategory.gaussians.rawValue, path: URL(fileURLWithPath: "/GameData/Gaussians/CHAIR.UNTOLDGS"))
        XCTAssertNotNil(GaussianTwinInspector.assignablePayloadURL(from: upperCase))

        let ply = Asset(name: "chair", category: AssetCategory.gaussians.rawValue, path: URL(fileURLWithPath: "/GameData/Gaussians/chair.ply"))
        XCTAssertNil(GaussianTwinInspector.assignablePayloadURL(from: ply), "sources must be cooked")

        let model = Asset(name: "chair", category: AssetCategory.models.rawValue, path: URL(fileURLWithPath: "/GameData/Models/chair.untoldgs"))
        XCTAssertNil(GaussianTwinInspector.assignablePayloadURL(from: model), "wrong category")

        let folder = Asset(name: "Captures", category: AssetCategory.gaussians.rawValue, path: URL(fileURLWithPath: "/GameData/Gaussians/Captures.untoldgs"), isFolder: true)
        XCTAssertNil(GaussianTwinInspector.assignablePayloadURL(from: folder))
        XCTAssertNil(GaussianTwinInspector.assignablePayloadURL(from: nil))
    }
}
