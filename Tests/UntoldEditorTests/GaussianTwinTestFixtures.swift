//
//  GaussianTwinTestFixtures.swift
//  UntoldEditorTests
//
//  Builds the on-disk and in-scene fixtures the Splat Twin tests share: a tiny `.untold`
//  written with the engine's public record encoders (the same layout the engine's own asset
//  tests build), a real version 3 `.untoldgs`, and scene entities wired the way the engine
//  registers a placed asset.
//

import Foundation
import simd
@testable import UntoldEditor
@testable import UntoldEngine

enum GaussianTwinTestFixtures {
    static func makeTemporaryDirectory(_ name: String = "GaussianTwinTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - .untold

    /// The shapes of entity table a fixture `.untold` can have.
    enum Layout {
        /// One mesh-bearing root `root_entity#0`, as a single-node asset is exported.
        case singleMesh
        /// A mesh-less root `root_entity#0` with one mesh child `child#1`; `secondChild` adds a
        /// mesh child `child2#2`; `namelessChild` writes `child#1` without a name (nameOffset
        /// `UntoldFormat.invalidIndex`), which the engine loader calls `entity_1`.
        case hierarchy(secondChild: Bool = false, namelessChild: Bool = false)
        /// Two root-level mesh records `legs#0` and `seat#1` and no hierarchy, as a re-export
        /// that split a single-node asset in two would be laid out.
        case twoRootMeshes
    }

    /// A `.untold` tile whose entity table is one mesh-bearing root (`hierarchy == false`) or a
    /// mesh-less root `root_entity#0` with one mesh child `child#1` (`hierarchy == true`), as a
    /// multi-node asset is exported. Uncompressed chunks; content hash computed.
    @discardableResult
    static func writeUntold(to directory: URL, name: String = "Chair", hierarchy: Bool = false) throws -> URL {
        try writeUntold(to: directory, name: name, layout: hierarchy ? .hierarchy() : .singleMesh)
    }

    @discardableResult
    static func writeUntold(to directory: URL, name: String = "Chair", layout: Layout) throws -> URL {
        let url = directory.appendingPathComponent("\(name).untold")
        try makeUntoldData(layout: layout).write(to: url)
        return url
    }

    /// The node path the engine derives for the mesh child of a `hierarchy` fixture.
    static let hierarchyChildNodePath = "Root/root_entity#0/child#1"
    /// … for the second mesh child of a `hierarchy(secondChild: true)` fixture.
    static let hierarchySecondChildNodePath = "Root/root_entity#0/child2#2"
    /// … for the child of a `hierarchy(namelessChild: true)` fixture.
    static let hierarchyNamelessChildNodePath = "Root/root_entity#0/entity_1#1"

    static func makeUntoldData(hierarchy: Bool) -> Data {
        makeUntoldData(layout: hierarchy ? .hierarchy() : .singleMesh)
    }

    static func makeUntoldData(layout: Layout) -> Data {
        let strings = ["root_entity", "child", "child2", "legs", "seat", "mesh_0", "mat_0", "albedo.ktx2"]
        let stringTable = makeStringTable(strings)
        let bounds = UntoldAABB(min: SIMD3<Float>(-1, -1, -1), max: SIMD3<Float>(1, 1, 1))

        let vertexWriter = UntoldBinaryWriter()
        for position in [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)] {
            UntoldPBRStaticVertexV1(
                position: position,
                normalPacked: UntoldVertexPacking.packNormal(SIMD3<Float>(0, 0, 1)),
                tangentPacked: UntoldVertexPacking.packTangent(SIMD3<Float>(1, 0, 0), handedness: 1)
            ).encode(to: vertexWriter)
        }
        let vertexData = vertexWriter.data
        let indexWriter = UntoldBinaryWriter()
        for index in [0, 1, 2] as [UInt16] {
            indexWriter.writeUInt16LE(index)
        }
        let indexData = indexWriter.data

        // (entity id, parent, name, has a mesh) in entity-table order.
        let plan: [(id: UInt32, parent: UInt32, name: String?, mesh: Bool)]
        switch layout {
        case .singleMesh:
            plan = [(0, UntoldFormat.invalidIndex, "root_entity", true)]
        case let .hierarchy(secondChild, namelessChild):
            var nodes: [(id: UInt32, parent: UInt32, name: String?, mesh: Bool)] = [
                (0, UntoldFormat.invalidIndex, "root_entity", false),
                (1, 0, namelessChild ? nil : "child", true),
            ]
            if secondChild {
                nodes.append((2, 0, "child2", true))
            }
            plan = nodes
        case .twoRootMeshes:
            plan = [(0, UntoldFormat.invalidIndex, "legs", true), (1, UntoldFormat.invalidIndex, "seat", true)]
        }

        var entities: [UntoldEntityRecordV1] = []
        var meshes: [UntoldMeshRecordV1] = []
        for node in plan {
            entities.append(UntoldEntityRecordV1(
                entityId: node.id,
                parentEntityId: node.parent,
                nameOffset: node.name.map { stringTable.offsets[$0]! } ?? UntoldFormat.invalidIndex,
                firstMeshRecordIndex: UInt32(meshes.count),
                meshRecordCount: node.mesh ? 1 : 0,
                localBounds: bounds,
                worldBounds: bounds
            ))
            if node.mesh {
                meshes.append(UntoldMeshRecordV1(
                    entityId: node.id,
                    meshNameOffset: stringTable.offsets["mesh_0"]!,
                    materialIndex: 0,
                    indexType: .uint16,
                    vertexCount: 3,
                    indexCount: 3,
                    vertexStrideBytes: 32,
                    vertexDataOffset: 0,
                    indexDataOffset: 0,
                    vertexDataSizeBytes: UInt64(vertexData.count),
                    indexDataSizeBytes: UInt64(indexData.count),
                    estimatedGPUBytes: UInt64(vertexData.count + indexData.count),
                    localBounds: bounds
                ))
            }
        }
        let material = UntoldMaterialRecordV1(nameOffset: stringTable.offsets["mat_0"]!, baseColorTextureIndex: 0)
        let texture = UntoldTextureRefRecordV1(
            nameOffset: stringTable.offsets["albedo.ktx2"]!,
            uriOffset: stringTable.offsets["albedo.ktx2"]!,
            textureFormat: .rgba8,
            width: 16,
            height: 16,
            mipCount: 1
        )

        var header = UntoldFileHeaderV1(
            fileType: .tile,
            chunkCount: 0,
            meshCount: UInt32(meshes.count),
            materialCount: 1,
            textureRefCount: 1,
            entityCount: UInt32(entities.count),
            vertexLayout: .pbrStaticV1,
            worldBounds: bounds
        )

        // (type, bytes, element count)
        let payloads: [(UntoldChunkType, Data, UInt32)] = [
            (.stringTable, stringTable.data, 0),
            (.entityTable, encodeRecords(entities), UInt32(entities.count)),
            (.meshTable, encodeRecords(meshes), UInt32(meshes.count)),
            (.materialTable, encodeRecords([material]), 1),
            (.textureTable, encodeRecords([texture]), 1),
            (.vertexData, vertexData, 0),
            (.indexData, indexData, 0),
        ]
        header.chunkCount = UInt32(payloads.count)
        return buildFileData(header: header, payloads: payloads)
    }

    private static func encodeRecords(_ records: [some UntoldBinaryEncodable]) -> Data {
        let writer = UntoldBinaryWriter()
        for record in records {
            record.encode(to: writer)
        }
        return writer.data
    }

    private static func makeStringTable(_ strings: [String]) -> (data: Data, offsets: [String: UInt32]) {
        let writer = UntoldBinaryWriter()
        var offsets: [String: UInt32] = [:]
        for string in strings {
            offsets[string] = UInt32(writer.count)
            writer.writeNullTerminatedUTF8(string)
        }
        return (writer.data, offsets)
    }

    /// Header, chunk table, then every payload on `UntoldFormat.fileAlignment`, with the
    /// content hash filled in from the laid-out chunks.
    private static func buildFileData(header: UntoldFileHeaderV1, payloads: [(UntoldChunkType, Data, UInt32)]) -> Data {
        var header = header
        let headerWriter = UntoldBinaryWriter()
        header.encode(to: headerWriter)
        let alignment = Int(UntoldFormat.fileAlignment)
        func aligned(_ value: Int) -> Int {
            let remainder = value % alignment
            return remainder == 0 ? value : value + (alignment - remainder)
        }

        var runningOffset = headerWriter.count + 40 * payloads.count
        var entries: [UntoldChunkEntryV1] = []
        for (chunkType, bytes, elementCount) in payloads {
            runningOffset = aligned(runningOffset)
            entries.append(UntoldChunkEntryV1(
                chunkType: chunkType,
                compressionType: .none,
                fileOffset: UInt64(runningOffset),
                compressedSize: UInt64(bytes.count),
                uncompressedSize: UInt64(bytes.count),
                elementCount: elementCount
            ))
            runningOffset += bytes.count
        }

        func layOut(_ header: UntoldFileHeaderV1) -> Data {
            let writer = UntoldBinaryWriter()
            header.encode(to: writer)
            for entry in entries {
                entry.encode(to: writer)
            }
            for (_, bytes, _) in payloads {
                writer.align(to: alignment)
                writer.writeData(bytes)
            }
            return writer.data
        }

        let unhashed = layOut(header)
        header.contentHash = Array((try? UntoldFormat.contentHash(of: entries, in: unhashed)) ?? Data(count: 32))
        return layOut(header)
    }

    // MARK: - .untoldgs

    /// A real version 3 payload with `splatCount` splats.
    @discardableResult
    static func writeUntoldGS(to url: URL, splatCount: Int = 3) throws -> URL {
        let splats = (0 ..< splatCount).map { index in
            UntoldGSSplat(
                position: SIMD3<Float>(Float(index) * 0.1, 0, 0),
                scale: SIMD3<Float>(repeating: 0.05),
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                color: SIMD3<Float>(0.5, 0.5, 0.5),
                opacity: 0.9
            )
        }
        try UntoldGSFormat.write(splats: splats).write(to: url)
        return url
    }

    /// Bytes that are not a version 3 `.untoldgs` (the right magic, an older version).
    @discardableResult
    static func writeStalePayload(to url: URL) throws -> URL {
        let writer = UntoldBinaryWriter()
        writer.writeData(Data(UntoldGSFormat.magicBytes))
        writer.writeUInt32LE(2)
        writer.writeData(Data(count: 256))
        try writer.data.write(to: url)
        return url
    }

    // MARK: - Scene entities

    /// A mesh entity placed from a single-node `.untold`: render + transform components, the
    /// render component's asset URL set as `setEntityMeshAsync` would.
    static func makeMeshEntity(name: String = "Chair", assetURL: URL) -> EntityID {
        let entityId = createEntity()
        setEntityName(entityId: entityId, name: name)
        registerComponent(entityId: entityId, componentType: LocalTransformComponent.self)
        registerComponent(entityId: entityId, componentType: WorldTransformComponent.self)
        registerComponent(entityId: entityId, componentType: RenderComponent.self)
        scene.get(component: RenderComponent.self, for: entityId)?.assetURL = assetURL
        return entityId
    }

    /// A multi-node placement: the root carries `AssetInstanceComponent`, the child a
    /// `DerivedAssetNodeComponent` with `nodePath` plus (when `withMesh`) a render component.
    static func makeAssetInstance(assetURL: URL, nodePath: String, withMesh: Bool = true) -> (root: EntityID, node: EntityID) {
        let root = createEntity()
        setEntityName(entityId: root, name: assetURL.deletingPathExtension().lastPathComponent)
        registerComponent(entityId: root, componentType: LocalTransformComponent.self)
        registerComponent(entityId: root, componentType: WorldTransformComponent.self)
        registerComponent(entityId: root, componentType: AssetInstanceComponent.self)
        scene.get(component: AssetInstanceComponent.self, for: root)?.assetURL = assetURL

        let node = createEntity()
        setEntityName(entityId: node, name: "child")
        registerComponent(entityId: node, componentType: LocalTransformComponent.self)
        registerComponent(entityId: node, componentType: WorldTransformComponent.self)
        registerComponent(entityId: node, componentType: DerivedAssetNodeComponent.self)
        if let derived = scene.get(component: DerivedAssetNodeComponent.self, for: node) {
            derived.assetRootEntityId = root
            derived.nodePath = nodePath
        }
        if withMesh {
            registerComponent(entityId: node, componentType: RenderComponent.self)
        }
        return (root, node)
    }

    /// Another mesh node under an existing placement's root.
    static func addDerivedMeshNode(root: EntityID, nodePath: String, name: String = "child2") -> EntityID {
        let node = createEntity()
        setEntityName(entityId: node, name: name)
        registerComponent(entityId: node, componentType: LocalTransformComponent.self)
        registerComponent(entityId: node, componentType: WorldTransformComponent.self)
        registerComponent(entityId: node, componentType: DerivedAssetNodeComponent.self)
        if let derived = scene.get(component: DerivedAssetNodeComponent.self, for: node) {
            derived.assetRootEntityId = root
            derived.nodePath = nodePath
        }
        registerComponent(entityId: node, componentType: RenderComponent.self)
        return node
    }
}
