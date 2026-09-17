//
//  ComponentLibraryController.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import CryptoKit
import Foundation
import UntoldComponentKit
import UntoldEngine

extension Notification.Name {
    /// A freshly built library is waiting and play mode has to end before it can be loaded.
    /// `EditorView` answers by stopping play, which restores the pre-play scene.
    static let codeComponentsRequestStopPlay = Notification.Name("CodeComponents.RequestStopPlay")
}

/// Ties the pieces together: reacts to the project opening and closing, builds the project's
/// component sources (and its plugins' editor sources) off the main thread, and swaps the
/// result in between frames.
///
/// A failed build changes nothing: the last good libraries stay live and the errors are shown.
final class ComponentLibraryController: ObservableObject {
    static let shared = ComponentLibraryController()

    enum Phase: Equatable {
        case noProject
        /// A project is open but has nothing to compile yet.
        case noSources
        case building
        /// Built; waiting for play mode to end before loading.
        case waitingForPlayToStop
        case loaded
        case failed(String)
    }

    @Published private(set) var phase: Phase = .noProject
    @Published private(set) var layout: ComponentProjectLayout?
    @Published private(set) var diagnostics: [ComponentDiagnostic] = []
    @Published private(set) var rawOutput = ""
    @Published private(set) var libraries: [LoadedComponentLibrary] = []
    @Published private(set) var revision = 0
    @Published private(set) var lastBuildSeconds: Double?
    @Published private(set) var lastBuildDate: Date?
    @Published private(set) var toolchain: ComponentToolchain?
    @Published private(set) var sdk: ComponentSDK?
    /// Bytes of libraries from earlier revisions. They stay mapped for the life of the process.
    @Published private(set) var retiredBytes = 0
    @Published private(set) var extensionIssues: [String] = []
    @Published var rebuildOnSave = false {
        didSet {
            guard rebuildOnSave != oldValue, let projectKey else { return }
            UserDefaults.standard.set(rebuildOnSave, forKey: Self.rebuildOnSaveKey(projectKey))
            restartWatcher()
        }
    }

    /// Never reset: module names must stay unique for the life of the process, even when the
    /// same project is closed and opened again.
    private var revisionCounter = 0
    private var projectKey: String?
    private var assetBasePath: URL?
    private var watcher: ComponentSourceWatcher?
    private var basePathSubscription: AnyCancellable?
    private var pendingApply: (requests: [ComponentCompileRequest], seconds: Double)?
    private var rebuildRequestedWhileBuilding = false
    private var isActivated = false
    private let buildQueue = DispatchQueue(label: "com.untoldengine.editor.component-build", qos: .userInitiated)

    private init() {}

    // MARK: Activation

    /// Called once the renderer exists. Installs the kit's system and starts following the
    /// open project.
    func activate() {
        guard isActivated == false, EditorFeatureFlags.enableCodeComponents else { return }
        isActivated = true
        CodeComponentSystem.install()
        EngineExtensionRegistry.shared.register(EditorExtensionTicker())
        basePathSubscription = EditorAssetBasePath.shared.$basePath
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] basePath in
                self?.projectDidChange(assetBasePath: basePath)
            }
    }

    // MARK: Project lifecycle

    func projectDidChange(assetBasePath basePath: URL?) {
        tearDownCurrentProject()
        assetBasePath = basePath
        guard let basePath else {
            phase = .noProject
            return
        }

        let root = ComponentSourceLocator.projectRoot(forAssetBasePath: basePath)
        let key = Self.projectKey(for: root)
        projectKey = key
        sdk = ComponentSDK.resolve()
        layout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: sdk)
        rebuildOnSave = UserDefaults.standard.bool(forKey: Self.rebuildOnSaveKey(key))
        try? FileManager.default.removeItem(at: cacheDirectory(for: key))
        restartWatcher()

        if layout?.units.isEmpty ?? true {
            phase = .noSources
        } else {
            buildAndLoad()
        }
    }

    private func tearDownCurrentProject() {
        watcher?.stop()
        watcher = nil
        pendingApply = nil
        EditorExtensionHost.shared.unloadAll()
        CodeComponentSystem.shared.prepareForReload()
        unregisterLoadedTypes()
        retiredBytes += libraries.reduce(0) { $0 + $1.byteSize }
        libraries = []
        diagnostics = []
        rawOutput = ""
        extensionIssues = []
        layout = nil
        projectKey = nil
    }

    // MARK: Building

    /// Compiles every unit of the open project and, on success, loads the result.
    func buildAndLoad() {
        guard let basePath = assetBasePath, let projectKey else { return }
        if phase == .building {
            rebuildRequestedWhileBuilding = true
            return
        }

        let currentLayout = ComponentSourceLocator.layout(forAssetBasePath: basePath, sdk: sdk)
        layout = currentLayout
        guard currentLayout.units.isEmpty == false else {
            phase = .noSources
            return
        }
        guard let sdk else {
            fail(ComponentBuildError.sdkMissing.localizedDescription)
            return
        }

        let located: ComponentToolchain
        switch toolchain.map(Result<ComponentToolchain, ComponentBuildError>.success) ?? ComponentToolchain.locate() {
        case let .success(found):
            located = found
            toolchain = found
        case let .failure(error):
            fail(error.localizedDescription)
            return
        }
        if let required = sdk.recordedCompilerVersion, required != located.compilerVersion {
            fail(ComponentBuildError.compilerMismatch(editor: required, installed: located.compilerVersion).localizedDescription)
            return
        }

        revisionCounter += 1
        let buildRevision = revisionCounter
        let output = cacheDirectory(for: projectKey)
        let requests = currentLayout.units.map {
            ComponentCompileRequest(unit: $0, revision: buildRevision, outputDirectory: output, sdk: sdk, toolchain: located)
        }

        phase = .building
        let task = TaskCenter.begin("Building components", detail: "\(requests.count) module\(requests.count == 1 ? "" : "s")")

        buildQueue.async { [weak self] in
            var results: [ComponentCompileResult] = []
            for request in requests {
                task.setDetail(request.moduleName)
                let result = ComponentCompiler.compile(request) { task.attach(process: $0) }
                results.append(result)
                if result.succeeded == false {
                    break
                }
            }
            DispatchQueue.main.async {
                self?.buildDidFinish(requests: requests, results: results, task: task, projectKey: projectKey)
            }
        }
    }

    private func buildDidFinish(
        requests: [ComponentCompileRequest],
        results: [ComponentCompileResult],
        task: EditorTaskHandle,
        projectKey builtFor: String
    ) {
        // The project may have been closed or switched while the compiler ran.
        guard builtFor == projectKey else {
            task.markCancelled("Project changed")
            phase = assetBasePath == nil ? .noProject : phase
            return
        }

        let seconds = results.reduce(0) { $0 + $1.seconds }
        diagnostics = results.flatMap(\.diagnostics)
        rawOutput = results.map(\.output).joined()
        lastBuildSeconds = seconds
        lastBuildDate = Date()

        let succeeded = results.count == requests.count && results.allSatisfy(\.succeeded)
        if succeeded {
            task.succeed(String(format: "Built in %.2fs", seconds))
            if gameMode {
                pendingApply = (requests, seconds)
                phase = .waitingForPlayToStop
                NotificationCenter.default.post(name: .codeComponentsRequestStopPlay, object: nil)
            } else {
                apply(requests)
            }
        } else {
            let errors = diagnostics.filter { $0.severity == .error }
            for diagnostic in errors {
                Logger.logError(message: "[Components] \(diagnostic.fileName):\(diagnostic.line): \(diagnostic.message)", category: "Components")
            }
            let summary = errors.isEmpty ? "The compiler failed. See the Components panel for its output." : "\(errors.count) error\(errors.count == 1 ? "" : "s")"
            task.fail(summary)
            phase = .failed(summary)
        }

        if rebuildRequestedWhileBuilding {
            rebuildRequestedWhileBuilding = false
            buildAndLoad()
        }
    }

    private func fail(_ message: String) {
        Logger.logError(message: "[Components] \(message)", category: "Components")
        phase = .failed(message)
    }

    // MARK: Loading

    /// The reload protocol. Runs on the main thread between frames.
    private func apply(_ requests: [ComponentCompileRequest]) {
        guard let projectKey else { return }
        EditorExtensionHost.shared.unloadAll()
        CodeComponentSystem.shared.prepareForReload()
        unregisterLoadedTypes()

        var loaded: [LoadedComponentLibrary] = []
        var failure: String?
        for request in requests {
            switch ComponentLibraryLoader.load(request) {
            case let .success(library): loaded.append(library)
            case let .failure(error): failure = error.localizedDescription
            }
            if failure != nil {
                break
            }
        }

        // Even after a load failure, bind what did register so the scene is not left bare.
        CodeComponentSystem.shared.finishReload()
        EditorExtensionHost.shared.load(typeNames: loaded.flatMap(\.extensionNames), projectKey: projectKey)
        extensionIssues = EditorExtensionHost.shared.issues

        retiredBytes += libraries.reduce(0) { $0 + $1.byteSize }
        libraries = loaded
        revision = requests.first?.revision ?? revision

        if let failure {
            fail(failure)
        } else {
            phase = .loaded
            let components = loaded.flatMap(\.componentNames)
            Logger.log(message: "[Components] Loaded revision \(revision): \(components.isEmpty ? "no components" : components.joined(separator: ", "))", category: "Components")
            for entry in EditorExtensionHost.shared.live {
                let items = entry.menuIdentifiers.isEmpty ? "no menu items" : entry.menuIdentifiers.joined(separator: ", ")
                Logger.log(message: "[Components] Extension \(entry.name): \(items)", category: "Components")
            }
            for issue in extensionIssues {
                Logger.logWarning(message: "[Components] \(issue)", category: "Components")
            }
        }
        editorController?.refreshInspector()
    }

    /// Types from loaded libraries carry a revision above zero. They are dropped before a new
    /// revision registers, so a type that was deleted from the sources does not linger.
    private func unregisterLoadedTypes() {
        for entry in CodeComponentRegistry.shared.entries where entry.revision > 0 {
            CodeComponentRegistry.shared.unregister(name: entry.name)
        }
        for entry in EditorExtensionRegistry.shared.entries where entry.revision > 0 {
            EditorExtensionRegistry.shared.unregister(name: entry.name)
        }
    }

    // MARK: Play mode

    func playModeDidStart() {
        CodeComponentSystem.shared.startPlayMode()
        EditorExtensionHost.shared.playModeDidChange(true)
    }

    /// `restoring` is true when the editor is about to reload the pre-play snapshot; the
    /// pending library then waits for `playModeRestoreDidFinish()`.
    func playModeDidStop(restoring: Bool) {
        CodeComponentSystem.shared.stopPlayMode()
        EditorExtensionHost.shared.playModeDidChange(false)
        if restoring == false {
            applyPendingIfAny()
        }
    }

    func playModeRestoreDidFinish() {
        CodeComponentSystem.shared.bindPending()
        applyPendingIfAny()
    }

    private func applyPendingIfAny() {
        guard let pending = pendingApply else { return }
        pendingApply = nil
        apply(pending.requests)
    }

    // MARK: Creating the components folder

    /// Creates the project's components folder with a starter component and builds it.
    func createComponentPackage() throws {
        guard let layout else { return }
        let directory = layout.componentsDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let starter = directory.appendingPathComponent("Spinner.swift")
        if FileManager.default.fileExists(atPath: starter.path) == false {
            try Self.starterComponentSource.write(to: starter, atomically: true, encoding: .utf8)
        }
        Logger.log(message: "[Components] Created \(directory.path). To use these components in the game as well, add the UntoldComponentKit product to the app target and call CodeComponentRegistry.shared.discoverInMainExecutable() and CodeComponentSystem.install() at startup.", category: "Components")
        restartWatcher()
        buildAndLoad()
    }

    static let starterComponentSource = """
    import simd
    import UntoldComponentKit
    import UntoldEngine

    /// Spins its entity while the scene is playing.
    ///
    /// Add it to an entity from the Inspector, press Play, then change `speed` here and save:
    /// with "Rebuild on save" on, the editor picks the change up without restarting.
    final class Spinner: CodeComponent {
        @UntoldAttribute("Degrees per second", range: -360 ... 360) var speed: Float = 90
        @UntoldAttribute var axis: SIMD3<Float> = [0, 1, 0]

        override func onUpdate(deltaTime: Float) {
            guard simd_length(axis) > 0 else { return }
            rotateBy(entityId: entity, angle: speed * deltaTime, axis: simd_normalize(axis))
        }
    }

    """

    // MARK: Watching

    private func restartWatcher() {
        watcher?.stop()
        watcher = nil
        guard rebuildOnSave, let layout else { return }
        let watcher = ComponentSourceWatcher(directories: layout.watchedDirectories) { [weak self] in
            self?.buildAndLoad()
        }
        watcher.start()
        self.watcher = watcher
    }

    // MARK: Paths and keys

    static func projectKey(for projectRoot: URL) -> String {
        let digest = SHA256.hash(data: Data(projectRoot.standardizedFileURL.path.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func rebuildOnSaveKey(_ projectKey: String) -> String {
        "editor.components.\(projectKey).rebuildOnSave"
    }

    func cacheDirectory(for projectKey: String) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("com.untoldengine.studio/Components/\(projectKey)", isDirectory: true)
    }
}
