import CryptoKit
import Foundation
import UntoldEngine

private struct UntoldMaterialTarget {
    let assetURL: URL
    let materialIndex: Int
}

func resolveUntoldAssetURL(entityId: EntityID) -> URL? {
    if let derivedNode = scene.get(component: DerivedAssetNodeComponent.self, for: entityId),
       let assetInstance = scene.get(component: AssetInstanceComponent.self, for: derivedNode.assetRootEntityId),
       assetInstance.assetURL.pathExtension.lowercased() == "untold"
    {
        return assetInstance.assetURL
    }

    guard let assetURL = getAssetURL(entityId: entityId),
          assetURL.pathExtension.lowercased() == "untold"
    else {
        return nil
    }

    return assetURL
}

private func resolveUntoldMaterialTarget(entityId: EntityID, meshIndex: Int) throws -> UntoldMaterialTarget {
    guard let assetURL = resolveUntoldAssetURL(entityId: entityId) else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Selected mesh is not backed by a .untold asset."
        ])
    }

    let fileData = try Data(contentsOf: assetURL)
    let decoded = try UntoldReader().readAsset(from: fileData)
    guard let targetEntityRecord = resolveEntityRecordForMesh(entityId: entityId, meshIndex: meshIndex, decoded: decoded) else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Could not map the selected mesh to an entity record in the .untold file."
        ])
    }

    guard Int(targetEntityRecord.meshRecordCount) > meshIndex else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "Selected mesh index is out of range for the .untold entity record."
        ])
    }

    let meshRecordIndex = Int(targetEntityRecord.firstMeshRecordIndex) + meshIndex
    guard decoded.meshes.indices.contains(meshRecordIndex) else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "Could not locate the mesh record in the .untold file."
        ])
    }

    let meshRecord = decoded.meshes[meshRecordIndex]
    guard meshRecord.materialIndex != UntoldFormat.invalidIndex else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "Selected mesh does not reference a writable material record."
        ])
    }

    let materialIndex = Int(meshRecord.materialIndex)
    guard decoded.materials.indices.contains(materialIndex) else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 6, userInfo: [
            NSLocalizedDescriptionKey: "Material record index is out of range in the .untold file."
        ])
    }

    return UntoldMaterialTarget(assetURL: assetURL, materialIndex: materialIndex)
}

private func resolveEntityRecordForMesh(
    entityId: EntityID,
    meshIndex: Int,
    decoded: UntoldDecodedAsset
) -> UntoldEntityRecordV1? {
    if let derivedNode = scene.get(component: DerivedAssetNodeComponent.self, for: entityId) {
        let entitiesByID = Dictionary(uniqueKeysWithValues: decoded.entities.map { ($0.entityId, $0) })
        return decoded.entities.first { record in
            buildUntoldDecodedNodePath(entityID: record.entityId, entitiesByID: entitiesByID, decoded: decoded) == derivedNode.nodePath
        }
    }

    let meshBearingEntities = decoded.entities.filter { $0.meshRecordCount > 0 }
    if meshBearingEntities.count == 1 {
        return meshBearingEntities.first
    }

    return decoded.entities.first {
        $0.parentEntityId == UntoldFormat.invalidIndex && Int($0.meshRecordCount) > meshIndex
    }
}

private func buildUntoldDecodedNodePath(
    entityID: UInt32,
    entitiesByID: [UInt32: UntoldEntityRecordV1],
    decoded: UntoldDecodedAsset
) -> String {
    guard let entity = entitiesByID[entityID] else {
        return "Root/Unknown#\(entityID)"
    }

    let entityName = (try? decoded.string(at: entity.nameOffset)) ?? "Unknown"
    let segment = "\(entityName)#\(entity.entityId)"
    if entity.parentEntityId != UntoldFormat.invalidIndex {
        let parentPath = buildUntoldDecodedNodePath(
            entityID: entity.parentEntityId,
            entitiesByID: entitiesByID,
            decoded: decoded
        )
        return "\(parentPath)/\(segment)"
    }

    return "Root/\(segment)"
}

private func encodeMaterialTable(_ materials: [UntoldMaterialRecordV1]) -> Data {
    let writer = UntoldBinaryWriter()
    for material in materials {
        material.encode(to: writer)
    }
    return writer.data
}

private func computeUntoldContentHash(data: Data, chunks: [UntoldChunkEntryV1]) -> [UInt8] {
    let sortedChunks = chunks.sorted { $0.chunkType.rawValue < $1.chunkType.rawValue }
    var hashInput = Data()
    hashInput.reserveCapacity(sortedChunks.reduce(0) { $0 + Int($1.compressedSize) })

    for chunk in sortedChunks {
        let start = Int(chunk.fileOffset)
        let end = start + Int(chunk.compressedSize)
        guard data.indices.contains(start), end <= data.count else { continue }
        hashInput.append(data.subdata(in: start ..< end))
    }

    return Array(SHA256.hash(data: hashInput))
}

func persistAlphaMaterialOverridesToUntold(
    entityId: EntityID,
    meshIndex: Int,
    opacity: Float,
    alphaCutoff: Float,
    roughness: Float,
    metallic: Float,
    alphaMode: MaterialAlphaMode
) throws {
    let target = try resolveUntoldMaterialTarget(entityId: entityId, meshIndex: meshIndex)
    var fileData = try Data(contentsOf: target.assetURL)
    let decoded = try UntoldReader().readAsset(from: fileData)

    guard let materialChunk = decoded.chunks.first(where: { $0.chunkType == .materialTable }) else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "The .untold file does not contain a material table."
        ])
    }

    guard materialChunk.compressionType == .none else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 8, userInfo: [
            NSLocalizedDescriptionKey: "Compressed material tables are not supported by the editor patch flow."
        ])
    }

    var materials = decoded.materials
    var material = materials[target.materialIndex]
    material.baseColorFactor.w = max(0.0, min(1.0, opacity))
    material.alphaCutoff = max(0.0, min(1.0, alphaCutoff))
    material.roughnessFactor = max(0.0, min(1.0, roughness))
    material.metallicFactor = max(0.0, min(1.0, metallic))
    material.flags = (material.flags & ~UInt32(0b11)) | UInt32(alphaMode.rawValue)
    materials[target.materialIndex] = material

    let materialData = encodeMaterialTable(materials)
    let materialRange = Int(materialChunk.fileOffset) ..< Int(materialChunk.fileOffset + materialChunk.compressedSize)
    guard materialRange.count == materialData.count else {
        throw NSError(domain: "UntoldMaterialPersistence", code: 9, userInfo: [
            NSLocalizedDescriptionKey: "Material table size changed unexpectedly; aborting patch."
        ])
    }

    fileData.replaceSubrange(materialRange, with: materialData)

    var header = decoded.header
    header.contentHash = computeUntoldContentHash(data: fileData, chunks: decoded.chunks)
    let headerWriter = UntoldBinaryWriter()
    header.encode(to: headerWriter)
    fileData.replaceSubrange(0 ..< headerWriter.data.count, with: headerWriter.data)

    try fileData.write(to: target.assetURL, options: .atomic)
}
