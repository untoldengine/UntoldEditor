//
//  AssetPlacement.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
//  Placing an asset browser row in the scene, shared by the row double-click and
//  by drag-and-drop onto the viewport or the hierarchy: which assets the engine
//  can render directly (models and Gaussian splats, or the folder packages that
//  stand for them), the drag payload that carries a row between panels, the entity
//  creation itself, and the ground-plane hit that lands a viewport drop under the
//  cursor. Gaussians load through the editor's loader (`loadEditorGaussianAuto`),
//  so a dropped splat gets the same Inspector metadata as a double-clicked one.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

/// What an asset browser row puts on the drag pasteboard: a small JSON record,
/// not the file, so nothing is read from disk until the drop lands.
struct AssetDragPayload: Codable, Equatable, Transferable {
    /// The pasteboard type the payload travels under. A standard type on purpose:
    /// a custom `UTType(exportedAs:)` has to be declared in the app's Info.plist,
    /// which a SwiftPM debug binary does not have, and AppKit refuses to match an
    /// undeclared type at the drop, so every target silently rejected it.
    static let contentType: UTType = .json

    var name: String
    var category: String
    var path: URL
    var isFolder: Bool

    init(name: String, category: String, path: URL, isFolder: Bool = false) {
        self.name = name
        self.category = category
        self.path = path
        self.isFolder = isFolder
    }

    init(asset: Asset) {
        self.init(name: asset.name, category: asset.category, path: asset.path, isFolder: asset.isFolder)
    }

    var asset: Asset {
        Asset(name: name, category: category, path: path, isFolder: isFolder)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> AssetDragPayload {
        try JSONDecoder().decode(AssetDragPayload.self, from: data)
    }
}

/// A light type a Lights shelf row can create by drag or double-click, mirroring
/// `PlaceableAsset` for models and Gaussians.
enum PlaceableLightType: String, Codable, CaseIterable {
    case directional
    case point
    case spot
    case area

    var displayName: String {
        switch self {
        case .directional: return "Directional Light"
        case .point: return "Point Light"
        case .spot: return "Spot Light"
        case .area: return "Area Light"
        }
    }

    /// Matches the icon `hierarchyIconName(for:)` shows once the light is placed.
    var iconName: String {
        switch self {
        case .directional: return "sun.max"
        case .point: return "lightbulb"
        case .spot: return "flashlight.on.fill"
        case .area: return "square"
        }
    }
}

/// What a Lights shelf row puts on the drag pasteboard: no file is involved, just
/// which light type to create. Travels under the same standard `.json` type as
/// `AssetDragPayload` (see its comment for why a custom UTType doesn't work here);
/// `loadDroppedRowPayload` tells the two apart by which one successfully decodes.
struct LightDragPayload: Codable, Equatable, Transferable {
    static let contentType: UTType = .json

    var lightType: PlaceableLightType

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> LightDragPayload {
        try JSONDecoder().decode(LightDragPayload.self, from: data)
    }
}

/// A basic primitive a Primitives shelf row can create by drag or double-click,
/// mirroring `PlaceableLightType`.
enum PlaceablePrimitiveType: String, Codable, CaseIterable {
    case cube
    case sphere
    case plane

    var displayName: String {
        switch self {
        case .cube: return "Cube"
        case .sphere: return "Sphere"
        case .plane: return "Plane"
        }
    }

    var iconName: String {
        switch self {
        case .cube: return "cube"
        case .sphere: return "circle"
        case .plane: return "square"
        }
    }

    var meshes: [Mesh] {
        switch self {
        case .cube: return BasicPrimitives.createCube()
        case .sphere: return BasicPrimitives.createSphere()
        case .plane: return BasicPrimitives.createPlane()
        }
    }
}

/// What a Primitives shelf row puts on the drag pasteboard: no file is involved,
/// just which primitive to create. Travels under the same standard `.json` type as
/// `AssetDragPayload` (see its comment for why a custom UTType doesn't work here);
/// `loadDroppedRowPayload` tells the payload kinds apart by which one decodes.
struct PrimitiveDragPayload: Codable, Equatable, Transferable {
    static let contentType: UTType = .json

    var primitiveType: PlaceablePrimitiveType

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }

    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) throws -> PrimitiveDragPayload {
        try JSONDecoder().decode(PrimitiveDragPayload.self, from: data)
    }
}

/// Either shape a dropped row can carry: a file-backed asset browser row, a Lights
/// shelf row naming a light type, or a Primitives shelf row naming a primitive.
enum DroppedRowPayload {
    case asset(AssetDragPayload)
    case light(LightDragPayload)
    case primitive(PrimitiveDragPayload)
}

/// Decodes whichever payload `providers` carries and hands it to `completion` on the
/// main queue. All payload kinds travel under the same standard `.json` pasteboard
/// type, so the data is tried against each Codable shape in turn; their required
/// fields don't overlap, so at most one ever decodes. Returns `false` when no
/// provider carries one of them, so an `onDrop` can decline drops of other types
/// (the hierarchy's entity-id text, say).
@discardableResult
func loadDroppedRowPayload(from providers: [NSItemProvider], completion: @escaping (DroppedRowPayload) -> Void) -> Bool {
    let identifier = AssetDragPayload.contentType.identifier
    guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(identifier) }) else {
        return false
    }
    provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, error in
        guard let data else {
            Logger.log(message: "⚠️ Dropped row payload could not be read: \(error?.localizedDescription ?? "no data")")
            return
        }
        if let light = try? LightDragPayload.decode(data) {
            DispatchQueue.main.async { completion(.light(light)) }
        } else if let primitive = try? PrimitiveDragPayload.decode(data) {
            DispatchQueue.main.async { completion(.primitive(primitive)) }
        } else if let asset = try? AssetDragPayload.decode(data) {
            DispatchQueue.main.async { completion(.asset(asset)) }
        } else {
            Logger.log(message: "⚠️ Dropped row payload could not be read: invalid data")
        }
    }
    return true
}

/// An asset the scene can place as its own entity.
enum PlaceableAsset: Equatable {
    /// A `.untold` runtime asset (or a multi-model `.untoldpack`) from the Models category.
    case model(URL)
    /// A Gaussian splat `.ply` source or a baked `.untoldgs`; a `<base>_lodN.untoldgs`
    /// tier stands for the whole progressive set, which the editor's loader detects.
    case gaussian(URL)
}

/// Resolves `asset` to something `placeAsset` can create, or `nil` for the kinds
/// that attach to an existing entity or the environment instead (animations,
/// scripts, materials, scenes, HDR). A Models folder stands for its primary
/// `.untold` / `.untoldpack`, and a Gaussian package folder (an import keeps a
/// capture's tiers together in one) for its primary `.untoldgs` / `.ply`.
func placeableAsset(for asset: Asset) -> PlaceableAsset? {
    switch asset.category {
    case AssetCategory.models.rawValue:
        let url: URL
        if asset.isFolder {
            guard let primary = primaryRuntimeAsset(in: asset.path) else { return nil }
            url = primary
        } else {
            url = asset.path
        }
        guard runtimeModelAssetExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return .model(url)

    case AssetCategory.gaussians.rawValue:
        let url: URL
        if asset.isFolder {
            guard let primary = primaryGaussianAsset(in: asset.path) else { return nil }
            url = primary
        } else {
            url = asset.path
        }
        guard ["ply", "untoldgs"].contains(url.pathExtension.lowercased()) else { return nil }
        return .gaussian(url)

    default:
        return nil
    }
}

/// Status text for a drop the scene cannot place.
func unsupportedAssetDropMessage(for asset: Asset) -> String {
    if asset.isFolder, asset.category == AssetCategory.models.rawValue {
        return "No primary .untold found in \(asset.name)"
    }
    if asset.isFolder, asset.category == AssetCategory.gaussians.rawValue {
        return "No Gaussian asset found in \(asset.name)"
    }
    return "Only models (.untold, .untoldpack) and Gaussian splats (.ply, .untoldgs) can be dropped into the scene"
}

struct AssetPlacementResult {
    let entityId: EntityID
    let entityName: String
    let statusMessage: String
    /// The status reports a load the editor declined rather than a queued import.
    var isError = false
}

/// Creates a named entity for `placeable`, attaches the asset, selects the entity
/// and refreshes the hierarchy. `position` is world space; `nil` leaves the entity at
/// the origin. Models and Gaussians load asynchronously (the engine applies a model's
/// own root transform when it lands), so the position is set from the completion.
@discardableResult
func placeAsset(
    _ placeable: PlaceableAsset,
    at position: simd_float3? = nil,
    sceneGraphModel: SceneGraphModel,
    selectionManager: SelectionManager
) -> AssetPlacementResult {
    let entityId = createEntity()

    // Use a generated name to avoid duplicate names when importing repeatedly
    let uniqueName = generateEntityName()
    setEntityName(entityId: entityId, name: uniqueName)

    let statusMessage: String
    var isError = false
    switch placeable {
    case let .model(url):
        // The engine resolves an absolute path as-is, which is what a `.untoldpack`
        // needs to find its per-model files beside it.
        setEntityMeshAsync(
            entityId: entityId,
            filename: runtimeAssetFilenameForLoading(url),
            withExtension: url.pathExtension
        ) { success in
            if success {
                print("✅ Model imported: \(uniqueName)")
            } else {
                print("⚠️ Failed to load model, using fallback: \(uniqueName)")
            }
            if let position {
                translateTo(entityId: entityId, position: position)
            }
            // Refresh scene hierarchy after loading completes
            sceneGraphModel.refreshHierarchy()
        }
        statusMessage = "Importing model: \(uniqueName)..."

    case let .gaussian(url):
        // The editor's loader tells a progressive tier set from a single file, records
        // the asset for the Inspector, and reads a single file off the main thread.
        let accepted = loadEditorGaussianAuto(entityId: entityId, url: url) { success in
            if success {
                print("✅ Gaussian imported: \(uniqueName)")
            } else {
                print("⚠️ Failed to load Gaussian: \(url.lastPathComponent)")
            }
            if let position {
                translateTo(entityId: entityId, position: position)
            }
            sceneGraphModel.refreshHierarchy()
        }
        statusMessage = accepted
            ? "Queued Gaussian import: \(uniqueName) (see Console)"
            : "Unsupported Gaussian asset: \(url.lastPathComponent)"
        isError = !accepted
    }

    // Select the newly created entity in the editor
    selectionManager.selectedEntity = entityId

    return AssetPlacementResult(entityId: entityId, entityName: uniqueName, statusMessage: statusMessage, isError: isError)
}

/// Creates a named light entity of `kind`, mirroring `placeAsset`'s model case: a
/// generated name, the transform and scene-graph components every hierarchy entity
/// needs, the light component itself, an optional world-space position, then
/// selection and a hierarchy refresh. Unlike a model or Gaussian, a light has
/// nothing to load asynchronously, so the entity is ready immediately.
@discardableResult
func placeLight(
    _ kind: PlaceableLightType,
    at position: simd_float3? = nil,
    sceneGraphModel: SceneGraphModel,
    selectionManager: SelectionManager
) -> AssetPlacementResult {
    let entityId = createEntity()

    let uniqueName = generateEntityName()
    setEntityName(entityId: entityId, name: uniqueName)
    registerTransformComponent(entityId: entityId)
    registerSceneGraphComponent(entityId: entityId)

    switch kind {
    case .directional:
        createDirLight(entityId: entityId)
    case .point:
        createPointLight(entityId: entityId)
    case .spot:
        createSpotLight(entityId: entityId)
    case .area:
        createAreaLight(entityId: entityId)
    }

    if let position {
        translateTo(entityId: entityId, position: position)
    }

    selectionManager.selectedEntity = entityId
    sceneGraphModel.refreshHierarchy()

    return AssetPlacementResult(
        entityId: entityId,
        entityName: uniqueName,
        statusMessage: "Added \(kind.displayName): \(uniqueName)"
    )
}

/// Creates a named primitive entity of `kind`, mirroring `placeLight`. A dropped
/// primitive lands at `position`; `setEntityMeshDirect` registers the transform and
/// scene-graph components a primitive needs.
@discardableResult
func placePrimitive(
    _ kind: PlaceablePrimitiveType,
    at position: simd_float3? = nil,
    sceneGraphModel: SceneGraphModel,
    selectionManager: SelectionManager
) -> AssetPlacementResult {
    let entityId = createEntity()

    let uniqueName = generateEntityName()
    setEntityName(entityId: entityId, name: uniqueName)
    setEntityMeshDirect(entityId: entityId, meshes: kind.meshes, assetName: kind.displayName)

    if let position {
        translateTo(entityId: entityId, position: position)
    }

    selectionManager.selectedEntity = entityId
    sceneGraphModel.refreshHierarchy()

    return AssetPlacementResult(
        entityId: entityId,
        entityName: uniqueName,
        statusMessage: "Added \(kind.displayName): \(uniqueName)"
    )
}

/// Farthest ground hit a viewport drop will use; a near-horizontal view would
/// otherwise place the entity kilometres away, so beyond this the drop falls back
/// to the origin.
let maximumAssetDropDistance: Float = 500

/// World-space point on the Y = 0 ground plane under `location`, a point in the
/// viewport's SwiftUI coordinates (origin top-left). `nil` when the ray misses the
/// plane, the hit is farther than `maxDistance`, or the viewport has no size. Pure:
/// the camera comes in as its view matrix and projection so tests need no renderer.
func groundPlaneHit(
    atViewportLocation location: CGPoint,
    viewportSize: CGSize,
    cameraPosition: simd_float3,
    viewSpace: simd_float4x4,
    perspectiveSpace: simd_float4x4,
    maxDistance: Float = maximumAssetDropDistance
) -> simd_float3? {
    guard viewportSize.width > 0, viewportSize.height > 0 else { return nil }

    // The engine's ray helper expects AppKit view coordinates (origin bottom-left),
    // the frame the gesture recognizers on the unflipped Metal view report in.
    let mouse = simd_float2(Float(location.x), Float(viewportSize.height - location.y))
    let viewport = simd_float2(Float(viewportSize.width), Float(viewportSize.height))
    let direction = rayDirectionInWorldSpace(
        uMouseLocation: mouse,
        uViewPortDim: viewport,
        uPerspectiveSpace: perspectiveSpace,
        uViewSpace: viewSpace
    )
    guard direction.x.isFinite, direction.y.isFinite, direction.z.isFinite else { return nil }

    guard let hit = pickGroundPosition(rayOrigin: cameraPosition, rayDirection: direction),
          hit.distance <= maxDistance
    else {
        return nil
    }
    return hit.worldPosition
}

/// `groundPlaneHit` against the editor's scene camera and the live projection.
func sceneCameraGroundPlaneHit(atViewportLocation location: CGPoint, viewportSize: CGSize) -> simd_float3? {
    guard let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera()) else {
        return nil
    }
    return groundPlaneHit(
        atViewportLocation: location,
        viewportSize: viewportSize,
        cameraPosition: cameraComponent.localPosition,
        viewSpace: cameraComponent.viewSpace,
        perspectiveSpace: renderInfo.perspectiveSpace
    )
}
