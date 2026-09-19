//
//  EditorView+BottomDock.swift
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
    enum BottomPanelTab: Hashable {
        case assets
        case explore
        case console
        case tasks
        case components
    }

    /// Themed segmented selector matching the editor style (accent-filled active
    /// segment inside a rounded surface container).
    var editorPanelTabs: some View {
        HStack(spacing: 2) {
            panelTabButton(.assets, title: "Assets", icon: "shippingbox")
            panelTabButton(.explore, title: "Explore", icon: "square.grid.2x2")
            panelTabButton(.console, title: "Console", icon: "terminal")
            panelTabButton(.tasks, title: "Tasks", icon: "list.bullet.rectangle")
            if EditorFeatureFlags.enableCodeComponents {
                panelTabButton(.components, title: "Plugins", icon: "puzzlepiece.extension")
            }
        }
        .padding(3)
        .background(Color.editorSurface.opacity(0.6))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.editorDivider, lineWidth: 1)
        )
    }

    func panelTabButton(_ tab: BottomPanelTab, title: String, icon: String) -> some View {
        let isSelected = bottomPanelTab == tab
        let runningCount = tab == .tasks ? taskCenter.activeCount : 0
        return Button(action: { bottomPanelTab = tab }) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                if runningCount > 0 {
                    // Live badge so running work is visible even when another tab is selected.
                    Text("\(runningCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isSelected ? .editorTextInverse : .editorTextPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.editorTextPrimary.opacity(0.85) : Color.editorAccent)
                        .clipShape(Capsule())
                }
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
        .help(panelTabHelp(tab))
    }

    func panelTabHelp(_ tab: BottomPanelTab) -> String {
        switch tab {
        case .assets: return "Show Asset Browser. Right-click the asset area to import."
        case .explore: return "Browse asset packs."
        case .console: return "Show Console"
        case .tasks: return "Show background tasks (exports, cooks, builds, loads)"
        case .components: return "Show the project's code components: build status, loaded types, compiler errors"
        }
    }

    var bottomSearchPlaceholder: String {
        switch bottomPanelTab {
        case .assets: return "Filter assets"
        case .explore: return "Filter packs"
        case .console: return "Filter console"
        case .tasks: return "Filter tasks"
        case .components: return "Filter components"
        }
    }

    /// Bottom dock: a segmented Assets/Console selector (replacing the old
    /// native TabView tab strip) plus the selected panel below it.
    var editorBottomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                editorPanelTabs
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.editorTextSecondary)
                    ExplicitClickTextField(
                        text: $bottomSearchQuery,
                        placeholder: bottomSearchPlaceholder
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: 240)
                .background(Color.editorSurface.opacity(0.6))
                .cornerRadius(6)

                if bottomPanelTab == .console {
                    Toggle("Auto‑scroll", isOn: $consoleAutoScroll)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))

                    Button(action: { LogStore.shared.clear() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.editorTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Clear console")
                }

                if bottomPanelTab == .tasks {
                    Button(action: { taskCenter.cancelAll() }) {
                        Image(systemName: "stop.circle")
                            .foregroundColor(.editorTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(taskCenter.activeCount == 0)
                    .help("Cancel all running tasks")

                    Button(action: { taskCenter.clearFinished() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.editorTextSecondary)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Clear finished tasks")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.editorPanelBackground.opacity(0.9))

            Group {
                switch bottomPanelTab {
                case .assets:
                    AssetBrowserView(
                        assets: $assets,
                        selectedAsset: $selectedAsset,
                        navigation: assetBrowserNavigation,
                        selectionManager: selectionManager,
                        sceneGraphModel: sceneGraphModel,
                        searchQuery: $bottomSearchQuery,
                        editor_addEntityWithAsset: editor_addEntityWithAsset,
                        editor_loadSceneAuthoredFromAsset: editor_loadSceneAuthoredFromAsset
                    )
                case .explore:
                    AssetPackBrowserView(searchQuery: $bottomSearchQuery) {
                        NotificationCenter.default.post(name: .assetBrowserReload, object: nil)
                    }
                case .console:
                    LogConsoleView(searchQuery: $bottomSearchQuery, autoScroll: $consoleAutoScroll)
                case .tasks:
                    TasksPanelView(searchQuery: $bottomSearchQuery)
                case .components:
                    ComponentsPanelView(searchQuery: $bottomSearchQuery)
                }
            }
            .frame(height: 200)
            .clipped()
        }
    }
}
