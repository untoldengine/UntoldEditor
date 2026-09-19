//
//  SceneTabStripView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// The scene tabs along the top of the viewport panel: the project's scenes,
/// the loaded one in front with its unsaved dot, and `+` for a new scene.
/// Clicking another tab loads that scene through the unsaved-changes gate.
struct SceneTabStripView: View {
    static let height: CGFloat = 34

    @ObservedObject var sceneCatalog: ProjectSceneCatalog
    @ObservedObject var dirtyState = EditorSceneDirtyState.shared
    var activeSceneURL: URL?
    let onSelectScene: (URL) -> Void
    let onAddScene: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(SceneTab.tabs(catalog: sceneCatalog.scenes, activeURL: activeSceneURL, isDirty: dirtyState.isDirty)) { tab in
                SceneTabView(tab: tab) {
                    if let url = tab.url, tab.isActive == false {
                        onSelectScene(url)
                    }
                }
            }
            EditorIconButton(systemImage: "plus", size: 24, help: "Add New Scene", action: onAddScene)
                .padding(.bottom, 2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(Color.editorTabStrip)
        .clipped()
    }
}
