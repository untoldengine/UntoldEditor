//
//  AddComponentMenu.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import UntoldComponentKit
import UntoldEngine

/// The Inspector's Add Component button. One menu lists everything the selected entity can
/// take: the engine's components first, then, under their own heading, the components the
/// project's code and its plugins define. The button is hidden when there is nothing to add.
struct AddComponentMenu: View {
    let entityId: EntityID
    let engineComponents: [ComponentOption_Editor]
    let addEngineComponent: (Any.Type) -> Void
    let refreshView: () -> Void

    /// Observed so the list follows the component libraries as they load and reload.
    @ObservedObject private var library = ComponentLibraryController.shared

    static let codeSectionTitle = "From Code"

    var body: some View {
        let codeComponents = library.revision >= 0 ? ScenePluginInspectorView.addableTypes(for: entityId) : []

        if engineComponents.isEmpty == false || codeComponents.isEmpty == false {
            Menu {
                ForEach(engineComponents, id: \.id) { component in
                    Button(component.name) {
                        addEngineComponent(component.type)
                    }
                }
                if codeComponents.isEmpty == false {
                    Section(Self.codeSectionTitle) {
                        ForEach(codeComponents, id: \.name) { entry in
                            Button(entry.type.displayName) {
                                ScenePluginInspectorView.add(entry.name, to: entityId)
                                refreshView()
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Component")
                        .fontWeight(.regular)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.accentColor)
                .foregroundColor(.editorTextPrimary)
                .cornerRadius(6)
            }
            .menuStyle(.borderlessButton)
            .padding(.top, 8)
        }
    }
}
