//
//  DemoSceneCatalog.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation

enum EditorExperienceMode {
    case explore
    case edit
}

enum DemoSceneSource {
    case remoteManifest(URL)
    case bundledManifest(resourceName: String, fileExtension: String)
    case bundledAsset(resourceName: String, fileExtension: String)

    var resolvedURL: URL? {
        switch self {
        case let .remoteManifest(url):
            return url
        case let .bundledManifest(resourceName, fileExtension),
             let .bundledAsset(resourceName, fileExtension):
            return Bundle.main.url(forResource: resourceName, withExtension: fileExtension)
        }
    }

    var fileExtension: String {
        switch self {
        case let .remoteManifest(url):
            return url.pathExtension.isEmpty ? "json" : url.pathExtension.lowercased()
        case let .bundledManifest(_, fileExtension),
             let .bundledAsset(_, fileExtension):
            return fileExtension.lowercased()
        }
    }
}

struct DemoSceneCatalogItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let thumbnailName: String
    let systemImageName: String
    let tags: [String]
    let source: DemoSceneSource
    let cameraFrame: StreamModelCameraFrame?
    let loadsSceneAuthoredPayload: Bool
}

private let starterDemoMetadata: [String: (subtitle: String, systemImageName: String, tags: [String])] = [
    "dungeon": (
        subtitle: "A compact realtime dungeon scene for quick camera navigation.",
        systemImageName: "cube.transparent",
        tags: ["Streamed", "Realtime"]
    ),
    "city": (
        subtitle: "A stylized city stream that demonstrates larger scene navigation.",
        systemImageName: "building.2",
        tags: ["Streamed", "City"]
    ),
    "f1car": (
        subtitle: "A vehicle showcase with a simple orbit-friendly camera frame.",
        systemImageName: "car.side",
        tags: ["Showcase", "Orbit"]
    ),
    "airplane": (
        subtitle: "A small aircraft scene for inspecting model detail.",
        systemImageName: "airplane",
        tags: ["Showcase", "Orbit"]
    ),
    "porsche964": (
        subtitle: "A car presentation scene with a guided starter view.",
        systemImageName: "car",
        tags: ["Showcase", "Vehicle"]
    ),
]

let demoSceneCatalog: [DemoSceneCatalogItem] = starterStreamModels.map { item in
    let metadata = starterDemoMetadata[item.id] ?? (
        subtitle: "A ready-to-explore Untold Engine demo scene.",
        systemImageName: "sparkles.rectangle.stack",
        tags: ["Demo"]
    )

    return DemoSceneCatalogItem(
        id: item.id,
        title: item.title,
        subtitle: metadata.subtitle,
        thumbnailName: item.id,
        systemImageName: metadata.systemImageName,
        tags: metadata.tags,
        source: .remoteManifest(item.manifestURL),
        cameraFrame: item.cameraFrame,
        loadsSceneAuthoredPayload: false
    )
}
