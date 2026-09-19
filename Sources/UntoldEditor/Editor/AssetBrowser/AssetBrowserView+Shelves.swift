//
//  AssetBrowserView+Shelves.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UniformTypeIdentifiers
import UntoldComponentKit
import UntoldEngine

extension AssetBrowserView {
    /// Returns AnyView (not `some View`) so the recursive child call is allowed.
    /// `category == nil` marks a generic (non-category) folder such as the root
    /// or a custom directory created at root level. `url` may be nil for a
    /// category root when no project folder is set yet.
    /// Fixed left-tree entry for the Lights shelf: not backed by disk, so it has no
    /// children and doesn't participate in the directory/category selection state
    /// beyond the `lightsSelected` flag.
    var lightsCategoryRow: some View {
        let isSelected = navigation.lightsSelected
        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.clear)
                .frame(width: 10)

            Image(systemName: isSelected ? "lightbulb.fill" : "lightbulb")
                .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
            Text("Lights")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, 12)
        .background(isSelected ? Color.editorAccentSoft : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.lightsSelected = true
            navigation.primitivesSelected = false
            navigation.entitiesSelected = false
            selectedDirURL = nil
            selectedCategory = nil
            folderPathStack = []
            selectedAsset = nil
            selectedAssetName = nil
        }
    }

    /// Row for one light type: drags into the viewport or the hierarchy the same
    /// way an asset browser row does (see `placeLight` in AssetPlacement.swift),
    /// or places it at the origin on a double-click.
    func lightRow(_ kind: PlaceableLightType) -> some View {
        HStack {
            Image(systemName: kind.iconName)
                .foregroundColor(.editorTextTertiary)
            Text(kind.displayName)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(LightDragPayload(lightType: kind))
        .onTapGesture(count: 2) {
            let placement = placeLight(kind, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
        }
    }

    var lightsShelfView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PlaceableLightType.allCases, id: \.self) { kind in
                lightRow(kind)
            }
            entityPluginRows(on: .lights)
        }
    }

    /// Fixed left-tree entry for the Primitives shelf, mirroring `lightsCategoryRow`.
    var primitivesCategoryRow: some View {
        let isSelected = navigation.primitivesSelected
        return HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.clear)
                .frame(width: 10)

            Image(systemName: isSelected ? "cube.fill" : "cube")
                .foregroundColor(isSelected ? Color.editorAccent : .editorTextTertiary)
            Text("Primitives")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.editorTextPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .padding(.leading, 12)
        .background(isSelected ? Color.editorAccentSoft : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            navigation.primitivesSelected = true
            navigation.lightsSelected = false
            navigation.entitiesSelected = false
            selectedDirURL = nil
            selectedCategory = nil
            folderPathStack = []
            selectedAsset = nil
            selectedAssetName = nil
        }
    }

    /// Row for one primitive: drags into the viewport or the hierarchy the same way
    /// an asset browser row does (see `placePrimitive` in AssetPlacement.swift), or
    /// places it at the origin on a double-click.
    func primitiveRow(_ kind: PlaceablePrimitiveType) -> some View {
        HStack {
            Image(systemName: kind.iconName)
                .foregroundColor(.editorTextTertiary)
            Text(kind.displayName)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .draggable(PrimitiveDragPayload(primitiveType: kind))
        .onTapGesture(count: 2) {
            let placement = placePrimitive(kind, sceneGraphModel: sceneGraphModel, selectionManager: selectionManager)
            showStatus(placement.statusMessage, isError: placement.isError)
        }
    }

    var primitivesShelfView: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(PlaceablePrimitiveType.allCases, id: \.self) { kind in
                primitiveRow(kind)
            }
            entityPluginRows(on: .primitives)
        }
    }

    /// The kinds of entity loaded code added to `shelf` (see `EntityPlugin` in the component
    /// kit). They sit under the built-in rows and work the same way.
    func entityPluginRows(on shelf: UntoldEntityShelf) -> some View {
        EntityPluginShelfRows(
            shelf: shelf,
            sceneGraphModel: sceneGraphModel,
            selectionManager: selectionManager,
            showStatus: { message, isError in showStatus(message, isError: isError) }
        )
    }

    /// Left-tree entry for the Entities shelf, mirroring `lightsCategoryRow`. Hidden until
    /// loaded code adds an entity kind that belongs there.
    var entitiesCategoryRow: some View {
        EntityPluginsCategoryRow(isSelected: navigation.entitiesSelected) {
            navigation.entitiesSelected = true
            navigation.lightsSelected = false
            navigation.primitivesSelected = false
            selectedDirURL = nil
            selectedCategory = nil
            folderPathStack = []
            selectedAsset = nil
            selectedAssetName = nil
        }
    }

    var entitiesShelfView: some View {
        VStack(alignment: .leading, spacing: 4) {
            entityPluginRows(on: .entities)
        }
    }
}
