//
//  HierarchyFilter.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import UntoldEngine

/// The name filter over the hierarchy: which rows show for what was typed.
enum HierarchyFilter {
    /// The entities to show for `query`: every entity whose name contains it,
    /// case-insensitively, with everything under it, plus the ancestors that
    /// lead to it, so a match keeps its place in the tree. Nil when the query is
    /// blank: nothing is filtered. `children` and `name` read the tree, so the
    /// rule is testable without a scene.
    static func visibleEntities(matching query: String, roots: [EntityID], children: (EntityID) -> [EntityID], name: (EntityID) -> String) -> Set<EntityID>? {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.isEmpty == false else {
            return nil
        }
        var visible: Set<EntityID> = []
        for root in roots {
            _ = collect(root, needle: needle, children: children, name: name, into: &visible)
        }
        return visible
    }

    /// Adds `entityId` to `visible` when it matches (with its subtree) or when a
    /// descendant does. Returns whether it was added.
    private static func collect(_ entityId: EntityID, needle: String, children: (EntityID) -> [EntityID], name: (EntityID) -> String, into visible: inout Set<EntityID>) -> Bool {
        if name(entityId).localizedCaseInsensitiveContains(needle) {
            insertSubtree(entityId, children: children, into: &visible)
            return true
        }
        var shown = false
        for child in children(entityId) {
            if collect(child, needle: needle, children: children, name: name, into: &visible) {
                shown = true
            }
        }
        if shown {
            visible.insert(entityId)
        }
        return shown
    }

    private static func insertSubtree(_ entityId: EntityID, children: (EntityID) -> [EntityID], into visible: inout Set<EntityID>) {
        visible.insert(entityId)
        for child in children(entityId) {
            insertSubtree(child, children: children, into: &visible)
        }
    }
}
