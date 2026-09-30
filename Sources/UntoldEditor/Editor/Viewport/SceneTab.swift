//
//  SceneTab.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Foundation

/// One scene in the strip above the viewport.
struct SceneTab: Identifiable, Equatable {
    /// Nil for a loaded scene that has no file yet.
    let url: URL?
    let name: String
    /// The loaded scene.
    let isActive: Bool
    /// Unsaved changes; only the loaded scene can have them.
    let isDirty: Bool

    var id: String {
        url?.absoluteString ?? "untitled"
    }

    /// A scene's name for its tab and the hierarchy's root row: the file's
    /// name, or "Untitled Scene" before it has one.
    static func name(for url: URL?) -> String {
        url?.deletingPathExtension().lastPathComponent ?? "Untitled Scene"
    }

    /// The catalog's scenes in its order, the loaded one marked active. A loaded
    /// scene the catalog does not list (not saved yet, or saved outside the
    /// project's Scenes folder) comes first as a tab of its own.
    static func tabs(catalog: [ProjectSceneFile], activeURL: URL?, isDirty: Bool) -> [SceneTab] {
        var tabs: [SceneTab] = []
        if catalog.contains(where: { $0.url == activeURL }) == false {
            tabs.append(SceneTab(url: activeURL, name: name(for: activeURL), isActive: true, isDirty: isDirty))
        }
        for scene in catalog {
            let isActive = scene.url == activeURL
            tabs.append(SceneTab(url: scene.url, name: scene.name, isActive: isActive, isDirty: isActive && isDirty))
        }
        return tabs
    }
}
