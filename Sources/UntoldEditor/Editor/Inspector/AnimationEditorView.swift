//
//  AnimationEditorView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import simd
import SwiftUI
import UniformTypeIdentifiers
import UntoldEngine

private func onAddAnimation_Editor(entityId: EntityID, url: URL) {
    guard canAuthorAnimationComponent(entityId: entityId) else {
        print("⚠️ Select a mesh node to assign animation")
        return
    }

    let filename = url.deletingPathExtension().lastPathComponent
    let runtimeFilename = runtimeAssetFilenameForLoading(url)
    let withExtension = url.pathExtension

    setEntityAnimations(entityId: entityId, filename: runtimeFilename, withExtension: withExtension, name: filename)
    // changeAnimation(entityId: entityId, name: filename)

    for targetEntityId in editorAnimationBindingTargetEntities(for: entityId) {
        guard let animationComponent = scene.get(component: AnimationComponent.self, for: targetEntityId) else {
            continue
        }

        if animationComponent.animationsFilenames.contains(url) == false {
            animationComponent.animationsFilenames.append(url)
        }
    }
}

struct AnimationEditorView: View {
    let entityId: EntityID
    let asset: Asset?
    let refreshView: () -> Void

    var body: some View {
        Text("Animation Properties")
        // List of currently linked animations
        let animationClips: [String] = getAllAnimationClips(entityId: entityId)

        List {
            ForEach(animationClips, id: \.self) { animation in
                HStack {
                    Text(animation) // Display animation name
                    Spacer()
                    Button(action: {
                        removeAnimationClip(entityId: entityId, animationClip: animation)
                        refreshView()
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.editorError)
                    }
                }
            }
        }
        .frame(height: 100)
        .scrollContentBackground(.hidden) // Hide default background
        .background(Color.editorFill) // Apply a dark background
        .cornerRadius(8) // Optional: Add corner radius for a sleek look
        // Add animation UI
        HStack {
            Button(action: {
                let selectedCategory: AssetCategory = .animations
                if let assetPath = asset?.path, selectedCategory.rawValue == asset?.category {
                    onAddAnimation_Editor(entityId: entityId, url: assetPath)
                }
                refreshView()
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.editorTextPrimary)
                    Text("Assign")
                        .fontWeight(.regular)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.editorSurface)
                .foregroundColor(.editorTextPrimary)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.editorDivider, lineWidth: 1)
                )
                .shadow(color: Color.editorShadow, radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
}
