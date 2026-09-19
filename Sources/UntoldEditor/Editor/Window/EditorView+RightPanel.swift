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
    enum EnvEffectsTab: Hashable {
        case environment
        case effects
    }

    /// Right panel is contextual: the project shows Environment/Effects (with a
    /// themed segmented switch); a selected object shows the Inspector.
    @ViewBuilder
    var editorRightPanel: some View {
        if selectionManager.projectSelected {
            VStack(spacing: 0) {
                HStack {
                    envEffectsTabs
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.editorPanelBackground.opacity(0.9))
                .padding(.top, 5)

                Group {
                    switch rightPanelEnvTab {
                    case .environment:
                        EnvironmentView(
                            selectedAsset: $selectedAsset,
                            onLoadSceneAuthored: editor_loadSceneAuthoredFromAsset
                        )
                    case .effects:
                        PostProcessingEditorView(selectedAsset: $selectedAsset)
                    }
                }
                .editorPanel()
                .padding(5)
            }
        } else if selectionManager.sceneSelected {
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
            .editorPanel()
            .padding(5)
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

    var envEffectsTabs: some View {
        HStack(spacing: 2) {
            envTabButton(.environment, title: "Environment", icon: "sun.max")
            envTabButton(.effects, title: "Effects", icon: "cube")
        }
        .padding(3)
        .background(Color.editorSurface.opacity(0.6))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
    }

    func envTabButton(_ tab: EnvEffectsTab, title: String, icon: String) -> some View {
        let isSelected = rightPanelEnvTab == tab
        return Button(action: { rightPanelEnvTab = tab }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 12)
            .foregroundColor(isSelected ? .editorTextPrimary : .editorTextSecondary)
            .background(isSelected ? Color.editorAccent : Color.clear)
            .cornerRadius(5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
