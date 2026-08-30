//
//  EditorMenuCommands.swift
//
//
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//
//  Bridges the native macOS menu bar (built in AppKit, see main.swift) with the
//  SwiftUI editor. Menu items post these notifications; EditorView listens and
//  runs the matching action. Shared toggle state lives in a singleton so both
//  the menu (checkmarks) and SwiftUI can read/write it.
//
import Foundation

extension Notification.Name {
    /// Posted when asynchronous asset/tile loading finishes, so the Scene Graph
    /// can refresh to show the newly-loaded entities.
    static let sceneGraphNeedsRefresh = Notification.Name("sceneGraphNeedsRefresh")
    static let editorMenuNew = Notification.Name("editorMenuNew")
    static let editorMenuOpen = Notification.Name("editorMenuOpen")
    static let editorMenuNewScene = Notification.Name("editorMenuNewScene")
    static let editorMenuSaveProject = Notification.Name("editorMenuSaveProject")
    static let editorMenuSave = Notification.Name("editorMenuSave")
    static let editorMenuSaveAs = Notification.Name("editorMenuSaveAs")
    static let editorMenuReset = Notification.Name("editorMenuReset")
}

/// Playback-related settings that must be reachable from both the AppKit menu
/// bar and SwiftUI views. Currently holds the "use the scene camera while
/// playing" toggle that used to live in the top toolbar.
final class EditorPlaybackSettings: ObservableObject {
    static let shared = EditorPlaybackSettings()

    @Published var useSceneCameraDuringPlay: Bool = false

    private init() {}
}

/// Which editor panels are visible. Shared between the AppKit View menu (for
/// checkmarks) and SwiftUI (to show/hide the panels).
final class EditorPanelVisibility: ObservableObject {
    static let shared = EditorPanelVisibility()

    @Published var showLeftPanel: Bool = true
    @Published var showBottomPanel: Bool = true
    @Published var showRightPanel: Bool = true

    /// Saved layout used by the "focus viewport" toggle (⌘F).
    private var savedLayout: (left: Bool, bottom: Bool, right: Bool)?

    private init() {}

    private var anyPanelVisible: Bool {
        showLeftPanel || showBottomPanel || showRightPanel
    }

    /// Hide every panel to show only the viewport; toggling again restores the
    /// panels that were visible before (not necessarily all of them).
    func toggleFocusViewport() {
        if anyPanelVisible {
            savedLayout = (showLeftPanel, showBottomPanel, showRightPanel)
            showLeftPanel = false
            showBottomPanel = false
            showRightPanel = false
        } else {
            let layout = savedLayout ?? (true, true, true)
            showLeftPanel = layout.left
            showBottomPanel = layout.bottom
            showRightPanel = layout.right
        }
    }
}
