//
//  ProjectSceneCatalog.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
//  Lists the scene files that live in the current project's `Scenes` folder so
//  the Scene Graph panel can present them as children of the project. The engine
//  only keeps one scene loaded at a time, so only the active scene shows live
//  elements; the rest are file references that load on demand.
//
import Combine
import Foundation
import UntoldEngine

struct ProjectSceneFile: Identifiable, Hashable {
    let url: URL
    let name: String

    var id: URL {
        url
    }
}

final class ProjectSceneCatalog: ObservableObject {
    @Published private(set) var scenes: [ProjectSceneFile] = []

    /// Rescan the project's `Scenes` directory. Safe to call often; it only
    /// touches the filesystem, not the ECS world.
    func refresh() {
        guard let basePath = EditorAssetBasePath.shared.basePath else {
            scenes = []
            return
        }

        let scenesDir = basePath.appendingPathComponent("Scenes", isDirectory: true)
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(
            at: scenesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            scenes = []
            return
        }

        scenes = items
            .filter { $0.pathExtension.lowercased() == untoldSceneFileExtension.lowercased() }
            .map { ProjectSceneFile(url: $0, name: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
