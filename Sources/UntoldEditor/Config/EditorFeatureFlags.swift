//
//  EditorFeatureFlags.swift
//  UntoldEditor
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//

import Foundation

/// Feature flags for controlling experimental or deprecated features in the editor
enum EditorFeatureFlags {
    // MARK: - Build System Features

    /// Enable the Build button in the toolbar
    /// When disabled, users should use the `untoldengine-create` CLI tool instead
    static let enableBuildButton: Bool = true

    // MARK: - Script Management Features

    /// Enable script creation and management buttons in the toolbar
    /// When disabled, users manage Swift code directly in their game project
    static let enableScriptButtons: Bool = true

    /// Enable the Script Component in the Inspector
    /// When disabled, users write game logic in Swift within their game project
    static let enableScriptComponent: Bool = true

    // MARK: - Future Use Cases

    // When these might be re-enabled:
    // - Build button: If we add specialized build configurations not available via CLI
    // - Script buttons: If we implement visual scripting / Blueprint-like system
    // - Script component: If we add hot-reloading or modding support via USC scripts
}

enum EditorAuthoringMode {
    /// Keep the editor focused on scene composition. Runtime behavior such as
    /// animation, kinetics, scripts, LOD, and batching should be wired in code.
    static let sceneCompositionOnly: Bool = true
}
