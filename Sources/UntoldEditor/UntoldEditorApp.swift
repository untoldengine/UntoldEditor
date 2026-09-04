//
//  UntoldEditorApp.swift
//  UntoldEngine
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import Combine
import MetalKit
import SwiftUI
import UntoldEngine

// AppDelegate: Boiler plate code
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var window: NSWindow!

    private let appName = "Untold Engine Editor"
    static let editorVersion = "0.18.1"

    private var projectTitleSubscription: AnyCancellable?

    /// Window title: "<project> - <app> v<version>" once a project is open,
    /// otherwise "<app> v<version>". The app name always stays next to the
    /// version so it reads as the editor's version, not the project's.
    static func windowTitle(projectName: String?, appName: String = "Untold Engine Editor", version: String = editorVersion) -> String {
        let editorLabel = "\(appName) v\(version)"
        if let projectName, !projectName.isEmpty {
            return "\(projectName) - \(editorLabel)"
        }
        return editorLabel
    }

    // View-menu items whose checkmark / enabled state is synced on open.
    private var showFPSItem: NSMenuItem?
    private var showFPSAdvancedItem: NSMenuItem?
    private var sceneCamItem: NSMenuItem?
    private var leftPanelItem: NSMenuItem?
    private var bottomPanelItem: NSMenuItem?
    private var rightPanelItem: NSMenuItem?

    func applicationDidFinishLaunching(_: Notification) {
        Logger.log(message: "Launching \(appName) v\(Self.editorVersion)")

        setupMainMenu()

        // Step 1. Create and configure the window
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = Self.windowTitle(projectName: nil, appName: appName)
        // Retitle the window whenever a project is opened, created, or closed.
        projectTitleSubscription = EditorAssetBasePath.shared.$basePath
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                window.title = Self.windowTitle(projectName: EditorAssetBasePath.shared.projectName, appName: appName)
            }
        // Force dark appearance so AppKit-drawn chrome (title bar, native tab
        // strips, segmented controls) matches the dark editor theme.
        window.appearance = NSAppearance(named: .darkAqua)
        // Tint the title bar with the editor background color instead of the
        // default near-black. Transparent title bar lets the window background
        // color (editorBackground) show through.
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(red: 0.15, green: 0.16, blue: 0.21, alpha: 1.0)
        window.center()

        let hostingView = NSHostingView(rootView: EditorView())
        window.contentView = hostingView

        window.makeKeyAndOrderFront(nil)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu bar

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App menu (first submenu is always treated as the application menu).
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // File menu
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu
        addItem(to: fileMenu, title: "New", action: #selector(menuNew), key: "n")
        addItem(to: fileMenu, title: "Open…", action: #selector(menuOpen), key: "o")
        addItem(to: fileMenu, title: "Save Project", action: #selector(menuSaveProject), key: "")
        fileMenu.addItem(.separator())
        let newScene = addItem(to: fileMenu, title: "Add New Scene", action: #selector(menuNewScene), key: "n")
        newScene.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, title: "Save Scene", action: #selector(menuSave), key: "s")
        let saveAs = addItem(to: fileMenu, title: "Save Scene As…", action: #selector(menuSaveAs), key: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(.separator())
        addItem(to: fileMenu, title: "Reset Scene", action: #selector(menuReset), key: "")

        // View menu (checkmarks are managed manually in menuNeedsUpdate).
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenu.autoenablesItems = false
        viewMenu.delegate = self
        viewMenuItem.submenu = viewMenu
        leftPanelItem = addItem(to: viewMenu, title: "Show Left Panel", action: #selector(menuToggleLeftPanel), key: "1")
        bottomPanelItem = addItem(to: viewMenu, title: "Show Bottom Panel", action: #selector(menuToggleBottomPanel), key: "2")
        rightPanelItem = addItem(to: viewMenu, title: "Show Right Panel", action: #selector(menuToggleRightPanel), key: "3")
        addItem(to: viewMenu, title: "Focus Viewport", action: #selector(menuToggleFocusViewport), key: "f")
        viewMenu.addItem(.separator())
        showFPSItem = addItem(to: viewMenu, title: "Show FPS", action: #selector(menuToggleFPS), key: "")
        showFPSAdvancedItem = addItem(to: viewMenu, title: "Show FPS Advanced", action: #selector(menuToggleFPSAdvanced), key: "")
        viewMenu.addItem(.separator())
        sceneCamItem = addItem(to: viewMenu, title: "Use Scene Camera During Play", action: #selector(menuToggleSceneCam), key: "")

        NSApp.mainMenu = mainMenu
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Keep the View-menu checkmarks in sync with the current overlay / camera state.
    func menuNeedsUpdate(_: NSMenu) {
        let store = EditorEngineStatsStore.shared
        showFPSItem?.state = store.overlayMode != .off ? .on : .off
        showFPSAdvancedItem?.state = store.overlayMode == .advanced ? .on : .off
        showFPSAdvancedItem?.isEnabled = store.overlayMode != .off
        sceneCamItem?.state = EditorPlaybackSettings.shared.useSceneCameraDuringPlay ? .on : .off

        let panels = EditorPanelVisibility.shared
        leftPanelItem?.state = panels.showLeftPanel ? .on : .off
        bottomPanelItem?.state = panels.showBottomPanel ? .on : .off
        rightPanelItem?.state = panels.showRightPanel ? .on : .off
    }

    // MARK: - File actions (bridged to SwiftUI via notifications)

    @objc private func menuNew() {
        NotificationCenter.default.post(name: .editorMenuNew, object: nil)
    }

    @objc private func menuOpen() {
        NotificationCenter.default.post(name: .editorMenuOpen, object: nil)
    }

    @objc private func menuNewScene() {
        NotificationCenter.default.post(name: .editorMenuNewScene, object: nil)
    }

    @objc private func menuSaveProject() {
        NotificationCenter.default.post(name: .editorMenuSaveProject, object: nil)
    }

    @objc private func menuSave() {
        NotificationCenter.default.post(name: .editorMenuSave, object: nil)
    }

    @objc private func menuSaveAs() {
        NotificationCenter.default.post(name: .editorMenuSaveAs, object: nil)
    }

    @objc private func menuReset() {
        NotificationCenter.default.post(name: .editorMenuReset, object: nil)
    }

    // MARK: - View actions (mutate shared stores directly)

    @objc private func menuToggleFPS() {
        let store = EditorEngineStatsStore.shared
        if store.overlayMode == .off {
            store.setOverlaySimplifiedEnabled(true)
        } else {
            store.setOverlaySimplifiedEnabled(false)
            store.setOverlayAdvancedEnabled(false)
        }
    }

    @objc private func menuToggleFPSAdvanced() {
        let store = EditorEngineStatsStore.shared
        if store.overlayMode == .advanced {
            store.setOverlaySimplifiedEnabled(true)
        } else {
            store.setOverlayAdvancedEnabled(true)
        }
    }

    @objc private func menuToggleSceneCam() {
        EditorPlaybackSettings.shared.useSceneCameraDuringPlay.toggle()
    }

    /// Animation + render-pause are driven by EditorView (which observes these
    /// values), so the menu just flips the state.
    @objc private func menuToggleLeftPanel() {
        EditorPanelVisibility.shared.showLeftPanel.toggle()
    }

    @objc private func menuToggleBottomPanel() {
        EditorPanelVisibility.shared.showBottomPanel.toggle()
    }

    @objc private func menuToggleRightPanel() {
        EditorPanelVisibility.shared.showRightPanel.toggle()
    }

    @objc private func menuToggleFocusViewport() {
        EditorPanelVisibility.shared.toggleFocusViewport()
    }
}

/// Entry point. An `@main` type rather than top-level code in a `main.swift`: Xcode 26
/// compiles a package executable that test targets import with `-parse-as-library`
/// (so `@testable import UntoldEditor` works), which forbids top-level statements.
/// `swift build` / `swift test` handle `@main` executables the same way.
@main
enum UntoldEditorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
