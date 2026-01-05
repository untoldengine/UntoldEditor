//
//  EditorController.swift
//  UntoldEngine
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
import AppKit
import Foundation
import simd
import UniformTypeIdentifiers
import UntoldEngine

public class EditorComponentsState: ObservableObject {
    public static let shared = EditorComponentsState()

    @Published public var components: [EntityID: [ObjectIdentifier: ComponentOption_Editor]] = [:]

    func clear() {
        components.removeAll()
    }
}

public class EditorAssetBasePath: ObservableObject {
    public static let shared = EditorAssetBasePath()

    private let userDefaultsKey = "UntoldEditor.AssetBasePath"

    @Published public var basePath: URL? {
        didSet {
            // Persist to UserDefaults whenever it changes
            if let url = basePath {
                UserDefaults.standard.set(url.path, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }

            // Sync with engine's global assetBasePath
            assetBasePath = basePath
        }
    }
    
    // Extract project name from the GameData path
    // e.g., /path/to/MyGame/Sources/MyGame/GameData -> "MyGame"
    public var projectName: String? {
        guard let basePath = basePath else { return nil }
        
        // GameData is at: ProjectRoot/Sources/ProjectName/GameData
        // So we go up 3 levels to get ProjectRoot
        let projectRoot = basePath.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return projectRoot.lastPathComponent
    }

    init() {
        // With the new workflow, editor should start with no asset path
        // The path will be set when user creates a new project via "New" button
        // or manually sets it via "Asset Folder" button
        basePath = nil
        assetBasePath = nil
        
        // Clear any previously persisted path since we're changing the workflow
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

class EditorController: SelectionDelegate, ObservableObject {
    let selectionManager: SelectionManager
    var isEnabled: Bool = false
    @Published var activeMode: TransformManipulationMode = .none
    @Published var activeAxis: TransformAxis = .none
    @Published var currentSceneURL: URL?

    init(selectionManager: SelectionManager) {
        self.selectionManager = selectionManager
        selectionDelegate = self
        isEnabled = true
    }

    func didSelectEntity(_ entityId: EntityID) {
        DispatchQueue.main.async {
            self.selectionManager.selectEntity(entityId: entityId)
        }
    }

    func resetActiveAxis() {
        activeAxis = .none
    }

    func refreshInspector() {
        DispatchQueue.main.async {
            self.selectionManager.objectWillChange.send()
        }
    }
}

// Notification to ask the Asset Browser to reload its listing
extension Notification.Name {
    static let assetBrowserReload = Notification.Name("AssetBrowser.Reload")
}

func saveScene(sceneData: SceneData) {
    let savePanel = NSSavePanel()
    savePanel.title = "Save Scene"
    savePanel.allowedContentTypes = [UTType.json]
    savePanel.nameFieldStringValue = "untitled.json"
    savePanel.canCreateDirectories = true
    savePanel.isExtensionHidden = false

    // If we have an asset base path, default the panel to the Scenes directory
    if let basePath = assetBasePath {
        let fm = FileManager.default
        let scenesRoot = basePath.appendingPathComponent("Scenes", isDirectory: true)
        // Ensure Scenes exists
        try? fm.createDirectory(at: scenesRoot, withIntermediateDirectories: true)
        savePanel.directoryURL = scenesRoot
    }

    savePanel.begin { result in
        if result == .OK, let url = savePanel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted

                let jsonData = try encoder.encode(sceneData)
                try jsonData.write(to: url)
                Logger.log(message: "Scene saved to picker location: \(url.path)")

                guard let basePath = assetBasePath else {
                    Logger.log(message: "Warning: assetBasePath is not set; cannot copy scene into Scenes folder.")
                    NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
                    return
                }

                let fm = FileManager.default
                let scenesRoot = basePath.appendingPathComponent("Scenes", isDirectory: true)
                try? fm.createDirectory(at: scenesRoot, withIntermediateDirectories: true)

                // Resolve symlinks and compare parents robustly
                let resolvedSaveURL = url.resolvingSymlinksInPath()
                let resolvedScenesRoot = scenesRoot.resolvingSymlinksInPath()
                let saveParent = resolvedSaveURL.deletingLastPathComponent()

                let isAlreadyInScenes = (saveParent == resolvedScenesRoot)
                let destURL = resolvedScenesRoot.appendingPathComponent(resolvedSaveURL.lastPathComponent)

                if isAlreadyInScenes {
                    Logger.log(message: "Scene already in Scenes folder: \(destURL.path)")
                } else {
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.copyItem(at: resolvedSaveURL, to: destURL)
                    Logger.log(message: "Scene copied into Scenes folder: \(destURL.path)")
                }

                NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
            } catch {
                Logger.log(message: "Failed to save scene: \(error)")
            }
        }
    }
}

/// Save directly to a URL (used by the inline save flow).
func saveSceneDirect(sceneData: SceneData, to url: URL) {
    do {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        let jsonData = try encoder.encode(sceneData)
        try jsonData.write(to: url)
        Logger.log(message: "Scene saved to \(url.path)")

        guard let basePath = assetBasePath else {
            Logger.log(message: "Warning: assetBasePath is not set; cannot copy scene into Scenes folder.")
            NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
            return
        }

        let fm = FileManager.default
        let scenesRoot = basePath.appendingPathComponent("Scenes", isDirectory: true)
        try? fm.createDirectory(at: scenesRoot, withIntermediateDirectories: true)

        let resolvedSaveURL = url.resolvingSymlinksInPath()
        let resolvedScenesRoot = scenesRoot.resolvingSymlinksInPath()
        let saveParent = resolvedSaveURL.deletingLastPathComponent()

        let isAlreadyInScenes = (saveParent == resolvedScenesRoot)
        let destURL = resolvedScenesRoot.appendingPathComponent(resolvedSaveURL.lastPathComponent)

        if isAlreadyInScenes {
            Logger.log(message: "Scene already in Scenes folder: \(destURL.path)")
        } else {
            if fm.fileExists(atPath: destURL.path) {
                try fm.removeItem(at: destURL)
            }
            try fm.copyItem(at: resolvedSaveURL, to: destURL)
            Logger.log(message: "Scene copied into Scenes folder: \(destURL.path)")
        }

        NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
    } catch {
        Logger.log(message: "Failed to save scene: \(error)")
    }
}

func loadGameScene() -> SceneData? {
    let openPanel = NSOpenPanel()
    openPanel.title = "Open Scene"
    openPanel.allowedContentTypes = [UTType.json]
    openPanel.allowsMultipleSelection = false

    if openPanel.runModal() == .OK, let url = openPanel.url {
        let decoder = JSONDecoder()

        do {
            let jsonData = try Data(contentsOf: url)
            let sceneData = try decoder.decode(SceneData.self, from: jsonData)

            Logger.log(message: "Scene loaded from \(url.path)")
            return sceneData
        } catch {
            Logger.log(message: "Failed to load scene: \(error)")
        }
    }

    return nil
}
