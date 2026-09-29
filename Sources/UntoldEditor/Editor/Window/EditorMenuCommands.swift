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
    /// Posted by the P key; the root view toggles play mode through the same
    /// snapshot-and-restore flow as the toolbar's Play button.
    static let editorTogglePlay = Notification.Name("editorTogglePlay")
    /// H over the editor: hide the selected entity.
    static let editorHideSelectedEntity = Notification.Name("editorHideSelectedEntity")
    /// ⌥H: show every hidden entity again.
    static let editorShowAllEntities = Notification.Name("editorShowAllEntities")
    /// ⌥1 to ⌥4: pick the tool named in `userInfo["tool"]`.
    static let editorSelectTool = Notification.Name("editorSelectTool")
    /// F: frame the selection.
    static let editorFrameSelection = Notification.Name("editorFrameSelection")
    /// View > Camera: show the game camera in `userInfo["camera"]`, or the
    /// editor's camera when there is none.
    static let editorShowViewportCamera = Notification.Name("editorShowViewportCamera")
}

/// Playback-related settings that must be reachable from both the AppKit menu
/// bar and SwiftUI views: the "use the scene camera while playing" toggle that
/// used to live in the top toolbar, and whether a play session is open.
final class EditorPlaybackSettings: ObservableObject {
    static let shared = EditorPlaybackSettings()

    @Published var useSceneCameraDuringPlay: Bool = false
    /// True from Play to Stop, paused or not: the play flow owns the viewport's
    /// camera, so the View menu offers no other.
    @Published var isSessionActive = false

    private init() {}
}
