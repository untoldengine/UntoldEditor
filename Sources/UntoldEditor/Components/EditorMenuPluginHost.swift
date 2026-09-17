//
//  EditorMenuPluginHost.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import UntoldComponentKit
import UntoldEngine

/// Owns the live `EditorMenuPlugin` instances of the loaded libraries: creates them, restores
/// and saves their menu values per project, builds their menus, and forwards editor events.
final class EditorMenuPluginHost {
    static let shared = EditorMenuPluginHost()

    struct LiveExtension {
        let name: String
        let instance: EditorMenuPlugin
        let menuIdentifiers: [String]
    }

    private(set) var live: [LiveExtension] = []
    /// Declarations that were refused: empty paths and paths another item already owns.
    private(set) var issues: [String] = []

    var menuHost: EditorMenuHost
    var defaults: UserDefaults
    private var projectKey = ""

    init(menuHost: EditorMenuHost = .shared, defaults: UserDefaults = .standard) {
        self.menuHost = menuHost
        self.defaults = defaults
    }

    // MARK: Loading

    /// Instantiates the named extension types. Persisted values are restored first, then the
    /// menus are built, then each extension hears `onLoad()` followed by one `menuDidChange`
    /// per stateful item so it can apply the restored state.
    func load(typeNames: [String], projectKey: String) {
        self.projectKey = projectKey
        issues.removeAll()
        menuHost.onValueChanged = { [weak self] owner, menu in
            self?.persist(menu)
            owner.menuDidChange(menu.domain, menu.pathComponents.joined(separator: "/"))
        }

        var claimed: Set<String> = []
        var accepted: [(owner: EditorMenuPlugin, menu: AnyUntoldMenu)] = []

        for name in typeNames.sorted() {
            guard let type = EditorMenuPluginRegistry.shared.type(named: name) else { continue }
            let instance = type.init()
            var identifiers: [String] = []
            for entry in instance.untoldMenuItems() {
                if entry.menu.pathComponents.isEmpty {
                    issues.append("\(name).\(entry.name): the menu path has no title.")
                    continue
                }
                if claimed.insert(entry.menu.identifier).inserted == false {
                    issues.append("\(name).\(entry.name): \"\(entry.menu.identifier)\" is already declared by another item.")
                    continue
                }
                restore(entry.menu)
                identifiers.append(entry.menu.identifier)
                accepted.append((instance, entry.menu))
            }
            live.append(LiveExtension(name: name, instance: instance, menuIdentifiers: identifiers))
        }

        menuHost.install(accepted)

        for entry in live {
            entry.instance.onLoad()
        }
        for (owner, menu) in accepted where menu.menuValue != nil {
            owner.menuDidChange(menu.domain, menu.pathComponents.joined(separator: "/"))
        }
    }

    func unloadAll() {
        for entry in live {
            entry.instance.onUnload()
        }
        live.removeAll()
        menuHost.removeAll()
    }

    // MARK: Editor events

    func sceneDidReset() {
        live.forEach { $0.instance.onSceneReset() }
    }

    func playModeDidChange(_ isPlaying: Bool) {
        live.forEach { $0.instance.onPlayModeChanged(isPlaying) }
    }

    func editorUpdate(deltaTime: Float) {
        live.forEach { $0.instance.onEditorUpdate(deltaTime: deltaTime) }
    }

    // MARK: Persistence

    static func persistenceKey(projectKey: String, identifier: String) -> String {
        "editor.menu.\(projectKey).\(identifier)"
    }

    private func restore(_ menu: AnyUntoldMenu) {
        guard menu.persists else { return }
        let key = Self.persistenceKey(projectKey: projectKey, identifier: menu.identifier)
        guard let stored = defaults.object(forKey: key) else { return }
        switch menu.kind {
        case .toggle:
            if let flag = stored as? Bool {
                menu.setMenuValue(.bool(flag))
            }
        case .choice:
            if let rawValue = stored as? String {
                // A case removed since the value was saved simply fails to apply; the default stays.
                menu.setMenuValue(.choice(rawValue))
            }
        case .action:
            break
        }
    }

    private func persist(_ menu: AnyUntoldMenu) {
        guard menu.persists else { return }
        let key = Self.persistenceKey(projectKey: projectKey, identifier: menu.identifier)
        switch menu.menuValue {
        case let .bool(flag): defaults.set(flag, forKey: key)
        case let .choice(rawValue): defaults.set(rawValue, forKey: key)
        case nil: break
        }
    }
}

/// Gives extensions their edit-mode frame callback.
final class EditorMenuPluginTicker: EngineExtension, @unchecked Sendable {
    static let extensionID = "com.untoldengine.editor.extension-host"
    let id = EditorMenuPluginTicker.extensionID

    func update(deltaTime: Float, context _: EngineExtensionUpdateContext) {
        guard gameMode == false else { return }
        EditorMenuPluginHost.shared.editorUpdate(deltaTime: deltaTime)
    }
}
