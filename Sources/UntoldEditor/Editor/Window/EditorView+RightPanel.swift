//
//  EditorView+RightPanel.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Combine
import MetalKit
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

extension EditorView {
    /// Right panel is contextual: the active scene node shows the scene
    /// inspector; otherwise it shows the selected entity's Inspector. Environment
    /// and Effects are their own dockable panels (see `PanelID`).
    @ViewBuilder
    var editorRightPanel: some View {
        if selectionManager.sceneSelected {
            sceneInspector
                .editorPanel()
                .padding(5)
        } else {
            InspectorView(
                selectionManager: selectionManager,
                sceneGraphModel: sceneGraphModel,
                onAddName_Editor: editor_addName,
                selectedAsset: $selectedAsset
            )
        }
    }

    /// Inspector shown when the active scene is selected in the Scene Graph.
    var sceneInspector: some View {
        let sceneName = editorController?.currentSceneURL?.deletingPathExtension().lastPathComponent ?? "Untitled Scene"
        return VStack(alignment: .leading, spacing: 10) {
            Text("Scene")
                .font(.headline)
                .foregroundColor(.editorTextPrimary)

            Divider()

            HStack {
                Text("Name")
                    .foregroundColor(.editorTextSecondary)
                Spacer()
                if editorController?.currentSceneURL != nil {
                    TextField("Scene name", text: $sceneNameDraft)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180)
                        .focused($isSceneNameFieldFocused)
                        .onSubmit {
                            commitSceneRename()
                            isSceneNameFieldFocused = false
                        }
                        .onChange(of: isSceneNameFieldFocused) { _, isFocused in
                            if isFocused == false {
                                commitSceneRename()
                            }
                        }
                } else {
                    Text(sceneName)
                        .foregroundColor(.editorTextPrimary)
                        .lineLimit(1)
                }
            }
            .font(.system(size: 12))
            .onAppear {
                sceneNameDraft = sceneName
            }
            .onChange(of: editorController?.currentSceneURL) { _, _ in
                sceneNameDraft = sceneName
            }

            if let url = editorController?.currentSceneURL {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Path")
                        .foregroundColor(.editorTextSecondary)
                    Text(url.path)
                        .foregroundColor(.editorTextTertiary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .font(.system(size: 11))
            } else {
                Text("This scene hasn't been saved yet.")
                    .font(.system(size: 11))
                    .foregroundColor(.editorTextTertiary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renames the active scene's file on disk to match `sceneNameDraft`, or
    /// reverts the draft if the new name is empty/invalid/already taken.
    func commitSceneRename() {
        guard let currentURL = editorController?.currentSceneURL else { return }
        let currentName = currentURL.deletingPathExtension().lastPathComponent
        let trimmed = sceneNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            sceneNameDraft = currentName
            return
        }
        guard trimmed != currentName else {
            return
        }
        guard trimmed.contains("/") == false else {
            sceneRenameFailedMessage = "Scene names can't contain \"/\"."
            showSceneRenameFailedAlert = true
            sceneNameDraft = currentName
            return
        }

        let newURL = currentURL.deletingLastPathComponent()
            .appendingPathComponent(trimmed)
            .appendingPathExtension(untoldSceneFileExtension)

        guard FileManager.default.fileExists(atPath: newURL.path) == false else {
            sceneRenameFailedMessage = "A scene named \"\(trimmed)\" already exists."
            showSceneRenameFailedAlert = true
            sceneNameDraft = currentName
            return
        }

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            editorController?.currentSceneURL = newURL
            sceneNameDraft = trimmed
            sceneCatalog.refresh()
        } catch {
            sceneRenameFailedMessage = "\(error)"
            showSceneRenameFailedAlert = true
            sceneNameDraft = currentName
        }
    }
}
