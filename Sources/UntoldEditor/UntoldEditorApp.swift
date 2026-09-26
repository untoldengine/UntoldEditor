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
    static let editorVersion = "0.20.0"

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
    private var panelMenuItems: [PanelID: [NSMenuItem]] = [:]
    private var dockMenuItem: NSMenuItem?
    private var navigationStyleItems: [CameraNavigationStyle: NSMenuItem] = [:]
    private var textureDebugItems: [TextureDebugOption: NSMenuItem] = [:]
    private var spatialDebugItems: [SpatialDebugOption: NSMenuItem] = [:]
    private var spatialDebugLeafColorModeItems: [SpatialDebugLeafColorModeOption: NSMenuItem] = [:]
    private var spatialDebugBatchCellColorModeItems: [SpatialDebugBatchCellColorModeOption: NSMenuItem] = [:]
    private var splatDebugItems: [SplatDebugOption: NSMenuItem] = [:]
    private var splatBlendCapItems: [SplatBlendCapOption: NSMenuItem] = [:]
    private var splatWorkingSetItems: [EditorSplatWorkingSet: NSMenuItem] = [:]
    private var splatLevelModeItems: [SplatLevelModeOption: NSMenuItem] = [:]

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
        window.backgroundColor = NSColor(Color.editorBackground)
        // The editor's toolbar row shares the title bar: the content view runs
        // under it, the title is hidden, and an empty unified toolbar gives the
        // title bar the height that centres the traffic lights in the row.
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        let titleBar = NSToolbar(identifier: "EditorTitleBar")
        titleBar.showsBaselineSeparator = false
        window.toolbar = titleBar
        window.toolbarStyle = .unified
        // The toolbar row drags the window through WindowDragRegion; nothing else
        // does, so a drag in the viewport or in a panel never moves the window.
        window.isMovableByWindowBackground = false
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
        addPanelItem(.hierarchy, to: viewMenu, title: "Show Hierarchy", key: "1")
        dockMenuItem = addItem(to: viewMenu, title: "Show Bottom Area", action: #selector(menuToggleDock), key: "2")
        dockMenuItem?.toolTip = "Hide or show the panels docked below the viewport"
        addPanelItem(.inspector, to: viewMenu, title: "Show Inspector", key: "3")
        addItem(to: viewMenu, title: "Focus Viewport", action: #selector(menuToggleFocusViewport), key: "f")
        viewMenu.addItem(.separator())
        // The dock panels one by one, so a panel closed from its tab comes back from here.
        for panel in PanelID.available where panel.defaultArea == .bottom {
            addPanelItem(panel, to: viewMenu, title: "Show \(panel.title)", key: "")
        }
        addItem(to: viewMenu, title: "Reset Layout", action: #selector(menuResetLayout), key: "")
        viewMenu.addItem(.separator())
        showFPSItem = addItem(to: viewMenu, title: "Show FPS", action: #selector(menuToggleFPS), key: "")
        showFPSAdvancedItem = addItem(to: viewMenu, title: "Show FPS Advanced", action: #selector(menuToggleFPSAdvanced), key: "")
        viewMenu.addItem(.separator())
        sceneCamItem = addItem(to: viewMenu, title: "Use Scene Camera During Play", action: #selector(menuToggleSceneCam), key: "")
        viewMenu.addItem(.separator())

        // Camera navigation style (radio-style checkmarks, synced in menuNeedsUpdate).
        let navigationItem = NSMenuItem(title: "Camera Navigation", action: nil, keyEquivalent: "")
        let navigationMenu = NSMenu(title: "Camera Navigation")
        navigationMenu.autoenablesItems = false
        for style in CameraNavigationStyle.allCases {
            let item = addItem(to: navigationMenu, title: style.title, action: #selector(menuSelectNavigationStyle(_:)), key: "")
            item.representedObject = style.rawValue
            item.toolTip = style.summary
            navigationStyleItems[style] = item
        }
        navigationItem.submenu = navigationMenu
        viewMenu.addItem(navigationItem)

        // Engine render-target visualizations (radio-style checkmarks). Lit restores the
        // regular rendered scene; the remaining choices expose G-buffer and post-process data.
        let textureDebugItem = NSMenuItem(title: "Texture Debug", action: nil, keyEquivalent: "")
        let textureDebugMenu = NSMenu(title: "Texture Debug")
        textureDebugMenu.autoenablesItems = false
        var textureDebugGroup: TextureDebugOption.Group?
        for option in TextureDebugOption.allCases {
            if let group = textureDebugGroup, group != option.group {
                textureDebugMenu.addItem(.separator())
            }
            textureDebugGroup = option.group
            let item = addItem(to: textureDebugMenu, title: option.title, action: #selector(menuSelectTextureDebug(_:)), key: "")
            item.representedObject = option.rawValue
            item.toolTip = option.summary
            textureDebugItems[option] = item
        }
        textureDebugItem.submenu = textureDebugMenu
        viewMenu.addItem(textureDebugItem)

        // Scene spatial-debug visualizations (SpatialDebugVisualization): LOD/streaming-tier
        // tinting, octree leaf bounds, streamed tile bounds and static-batch cell bounds.
        let spatialDebugItem = NSMenuItem(title: "Spatial Debug", action: nil, keyEquivalent: "")
        let spatialDebugMenu = NSMenu(title: "Spatial Debug")
        spatialDebugMenu.autoenablesItems = false
        var spatialDebugGroup: SpatialDebugOption.Group?
        for option in SpatialDebugOption.allCases {
            if let group = spatialDebugGroup, group != option.group {
                spatialDebugMenu.addItem(.separator())
            }
            if option.group == .octree, spatialDebugGroup != .octree {
                // Leaf color mode leads the octree group (radio items, synced in
                // menuNeedsUpdate); it also governs Tile Bounds' coloring below.
                let leafColorModeItem = NSMenuItem(title: "Leaf Color Mode", action: nil, keyEquivalent: "")
                let leafColorModeMenu = NSMenu(title: "Leaf Color Mode")
                leafColorModeMenu.autoenablesItems = false
                for mode in SpatialDebugLeafColorModeOption.allCases {
                    let modeItem = addItem(to: leafColorModeMenu, title: mode.title, action: #selector(menuSelectSpatialDebugLeafColorMode(_:)), key: "")
                    modeItem.representedObject = mode.rawValue
                    modeItem.toolTip = mode.summary
                    spatialDebugLeafColorModeItems[mode] = modeItem
                }
                leafColorModeItem.submenu = leafColorModeMenu
                spatialDebugMenu.addItem(leafColorModeItem)
            }
            if option.group == .batching, spatialDebugGroup != .batching {
                // Cell color mode leads the batching group (radio items, synced in
                // menuNeedsUpdate).
                let cellColorModeItem = NSMenuItem(title: "Cell Color Mode", action: nil, keyEquivalent: "")
                let cellColorModeMenu = NSMenu(title: "Cell Color Mode")
                cellColorModeMenu.autoenablesItems = false
                for mode in SpatialDebugBatchCellColorModeOption.allCases {
                    let modeItem = addItem(to: cellColorModeMenu, title: mode.title, action: #selector(menuSelectSpatialDebugBatchCellColorMode(_:)), key: "")
                    modeItem.representedObject = mode.rawValue
                    modeItem.toolTip = mode.summary
                    spatialDebugBatchCellColorModeItems[mode] = modeItem
                }
                cellColorModeItem.submenu = cellColorModeMenu
                spatialDebugMenu.addItem(cellColorModeItem)
            }
            spatialDebugGroup = option.group
            let item = addItem(to: spatialDebugMenu, title: option.title, action: #selector(menuToggleSpatialDebug(_:)), key: "")
            item.representedObject = option.rawValue
            item.toolTip = option.summary
            spatialDebugItems[option] = item
        }
        spatialDebugItem.submenu = spatialDebugMenu
        viewMenu.addItem(spatialDebugItem)

        // Gaussian splat debug switches (engine GaussianDebugOptions): each turns off one
        // stage of the splat pipeline so a rendering artefact can be bisected live.
        let splatDebugItem = NSMenuItem(title: "Splat Debug", action: nil, keyEquivalent: "")
        let splatDebugMenu = NSMenu(title: "Splat Debug")
        splatDebugMenu.autoenablesItems = false
        var splatDebugGroup: SplatDebugOption.Group?
        for option in SplatDebugOption.allCases {
            if let group = splatDebugGroup, group != option.group {
                splatDebugMenu.addItem(.separator())
            }
            if option.group == .paging, splatDebugGroup != .paging {
                // The per-pixel blend cap leads the paging group's separator (radio items).
                let blendCapItem = NSMenuItem(title: "Splat Blend Cap", action: nil, keyEquivalent: "")
                let blendCapMenu = NSMenu(title: "Splat Blend Cap")
                blendCapMenu.autoenablesItems = false
                for choice in SplatBlendCapOption.allCases {
                    let item = addItem(to: blendCapMenu, title: choice.title, action: #selector(menuSelectSplatBlendCap(_:)), key: "")
                    item.representedObject = choice.rawValue
                    item.toolTip = choice.summary
                    splatBlendCapItems[choice] = item
                }
                blendCapItem.submenu = blendCapMenu
                splatDebugMenu.addItem(blendCapItem)
                splatDebugMenu.addItem(.separator())
            }
            if option.group == .levels, splatDebugGroup != .levels {
                // The level mode leads its group (radio-style checkmarks, synced in menuNeedsUpdate).
                let levelModeItem = NSMenuItem(title: "Splat Level Mode", action: nil, keyEquivalent: "")
                let levelModeMenu = NSMenu(title: "Splat Level Mode")
                levelModeMenu.autoenablesItems = false
                for mode in SplatLevelModeOption.allCases {
                    let item = addItem(to: levelModeMenu, title: mode.title, action: #selector(menuSelectSplatLevelMode(_:)), key: "")
                    item.representedObject = mode.rawValue
                    item.toolTip = mode.summary
                    splatLevelModeItems[mode] = item
                }
                levelModeItem.submenu = levelModeMenu
                splatDebugMenu.addItem(levelModeItem)
            }
            splatDebugGroup = option.group
            let item = addItem(to: splatDebugMenu, title: option.title, action: #selector(menuToggleSplatDebug(_:)), key: "")
            item.representedObject = option.rawValue
            item.toolTip = option.summary
            splatDebugItems[option] = item
        }
        splatDebugMenu.addItem(.separator())

        // The working set the frame draws from (radio-style checkmarks, synced in
        // menuNeedsUpdate): the editor's frame-time budget for a large capture.
        let workingSetItem = NSMenuItem(title: "Working Set", action: nil, keyEquivalent: "")
        let workingSetMenu = NSMenu(title: "Working Set")
        workingSetMenu.autoenablesItems = false
        for choice in EditorSplatWorkingSet.allCases {
            let item = addItem(to: workingSetMenu, title: choice.title, action: #selector(menuSelectSplatWorkingSet(_:)), key: "")
            item.representedObject = choice.rawValue
            item.toolTip = choice.summary
            splatWorkingSetItems[choice] = item
        }
        workingSetItem.submenu = workingSetMenu
        splatDebugMenu.addItem(workingSetItem)
        splatDebugItem.submenu = splatDebugMenu
        viewMenu.addItem(splatDebugItem)

        // Window menu: the standard items; macOS appends the open windows.
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    /// A menu item that shows or hides a panel of the docking layout; its
    /// checkmark follows the layout in `menuNeedsUpdate`.
    private func addPanelItem(_ panel: PanelID, to menu: NSMenu, title: String, key: String) {
        let item = addItem(to: menu, title: title, action: #selector(menuTogglePanel(_:)), key: key)
        item.representedObject = panel.rawValue
        panelMenuItems[panel, default: []].append(item)
    }

    @discardableResult
    private func addItem(to menu: NSMenu, title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    /// Keep the View-menu checkmarks in sync with the current overlay / camera state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        // Items that loaded editor extensions added to this menu sync their own state.
        EditorMenuHost.shared.menuNeedsUpdate(menu)

        for (option, item) in splatDebugItems {
            item.state = option.isEnabled ? .on : .off
        }
        let textureDebug = TextureDebugOption.current
        for (option, item) in textureDebugItems {
            item.state = option == textureDebug ? .on : .off
        }
        for (option, item) in spatialDebugItems {
            item.state = option.isEnabled ? .on : .off
        }
        let leafColorMode = SpatialDebugLeafColorModeOption.current
        for (mode, item) in spatialDebugLeafColorModeItems {
            item.state = mode == leafColorMode ? .on : .off
        }
        let cellColorMode = SpatialDebugBatchCellColorModeOption.current
        for (mode, item) in spatialDebugBatchCellColorModeItems {
            item.state = mode == cellColorMode ? .on : .off
        }
        let workingSet = EditorGaussianRuntimeSettings.shared.workingSet
        for (choice, item) in splatWorkingSetItems {
            item.state = choice == workingSet ? .on : .off
        }
        let levelMode = SplatLevelModeOption.current
        for (mode, item) in splatLevelModeItems {
            item.state = mode == levelMode ? .on : .off
        }
        let blendCap = SplatBlendCapOption.current
        for (choice, item) in splatBlendCapItems {
            item.state = choice == blendCap ? .on : .off
        }
        let store = EditorEngineStatsStore.shared
        showFPSItem?.state = store.overlayMode != .off ? .on : .off
        showFPSAdvancedItem?.state = store.overlayMode == .advanced ? .on : .off
        showFPSAdvancedItem?.isEnabled = store.overlayMode != .off
        sceneCamItem?.state = EditorPlaybackSettings.shared.useSceneCameraDuringPlay ? .on : .off

        let layout = EditorDockLayout.shared
        for (panel, items) in panelMenuItems {
            for item in items {
                item.state = layout.isOpen(panel) ? .on : .off
            }
        }
        dockMenuItem?.state = layout.isVisible(.bottom) ? .on : .off

        let activeStyle = EditorNavigationSettings.shared.style
        for (style, item) in navigationStyleItems {
            item.state = style == activeStyle ? .on : .off
        }
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

    @objc private func menuSelectNavigationStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = CameraNavigationStyle(rawValue: raw)
        else {
            return
        }
        EditorNavigationSettings.shared.style = style
    }

    @objc private func menuSelectTextureDebug(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let option = TextureDebugOption(rawValue: raw)
        else {
            return
        }
        TextureDebugOption.current = option
    }

    @objc private func menuToggleSpatialDebug(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = SpatialDebugOption(rawValue: raw) else {
            return
        }
        option.isEnabled.toggle()
        sender.state = option.isEnabled ? .on : .off
    }

    @objc private func menuSelectSpatialDebugLeafColorMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SpatialDebugLeafColorModeOption(rawValue: raw)
        else {
            return
        }
        SpatialDebugLeafColorModeOption.current = mode
    }

    @objc private func menuSelectSpatialDebugBatchCellColorMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SpatialDebugBatchCellColorModeOption(rawValue: raw)
        else {
            return
        }
        SpatialDebugBatchCellColorModeOption.current = mode
    }

    @objc private func menuSelectSplatWorkingSet(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = EditorSplatWorkingSet(rawValue: raw) else {
            return
        }
        EditorGaussianRuntimeSettings.shared.workingSet = choice
    }

    @objc private func menuSelectSplatLevelMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = SplatLevelModeOption(rawValue: raw) else {
            return
        }
        SplatLevelModeOption.current = mode
    }

    @objc private func menuSelectSplatBlendCap(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let choice = SplatBlendCapOption(rawValue: raw) else {
            return
        }
        SplatBlendCapOption.current = choice
    }

    @objc private func menuToggleSplatDebug(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let option = SplatDebugOption(rawValue: raw) else {
            return
        }
        option.isEnabled.toggle()
        sender.state = option.isEnabled ? .on : .off
    }

    /// The docking layout is shared with SwiftUI, which renders whatever it holds.
    @objc private func menuTogglePanel(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let panel = PanelID(rawValue: raw) else {
            return
        }
        EditorDockLayout.shared.toggle(panel)
    }

    @objc private func menuToggleDock() {
        EditorDockLayout.shared.toggleArea(.bottom)
    }

    @objc private func menuToggleFocusViewport() {
        EditorDockLayout.shared.toggleFocusViewport()
    }

    @objc private func menuResetLayout() {
        EditorDockLayout.shared.reset()
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

/// The engine's render-target visualizations, presented as View > Texture Debug choices.
/// This editor-facing type supplies stable menu labels while keeping the engine enum as the
/// source of truth for rendering behavior.
enum TextureDebugOption: String, CaseIterable {
    case lit
    case albedo
    case normal
    case position
    case depth
    case roughness
    case metallic
    case height
    case pomOffset
    case ssaoBlurred
    case fxaaEdges
    case smaaEdges
    case smaaBlend
    case smaaDifference
    case occlusion
    case preTonemapHDRLuminance
    case postTonemapOutput

    enum Group: Int {
        case output
        case geometry
        case material
        case postProcess
        case diagnostics
    }

    var group: Group {
        switch self {
        case .lit: .output
        case .albedo, .normal, .position, .depth: .geometry
        case .roughness, .metallic, .height, .pomOffset: .material
        case .ssaoBlurred, .fxaaEdges, .smaaEdges, .smaaBlend, .smaaDifference: .postProcess
        case .occlusion, .preTonemapHDRLuminance, .postTonemapOutput: .diagnostics
        }
    }

    var title: String {
        switch self {
        case .lit: "Lit"
        case .albedo: "Albedo"
        case .normal: "Normal"
        case .position: "Position"
        case .depth: "Depth"
        case .roughness: "Roughness"
        case .metallic: "Metallic"
        case .height: "Height"
        case .pomOffset: "POM Offset"
        case .ssaoBlurred: "SSAO (Blurred)"
        case .fxaaEdges: "FXAA Edges"
        case .smaaEdges: "SMAA Edges"
        case .smaaBlend: "SMAA Blend"
        case .smaaDifference: "SMAA Difference"
        case .occlusion: "Occlusion"
        case .preTonemapHDRLuminance: "Pre-Tonemap HDR Luminance"
        case .postTonemapOutput: "Post-Tonemap Output"
        }
    }

    var summary: String {
        switch self {
        case .lit: "Show the regular lit scene."
        case .albedo: "Show the G-buffer albedo texture."
        case .normal: "Show the G-buffer normal texture."
        case .position: "Show world-space positions as repeating RGB bands."
        case .depth: "Show linearized scene depth."
        case .roughness: "Show the material roughness channel."
        case .metallic: "Show the material metallic channel."
        case .height: "Show the raw height-map sample used by parallax occlusion mapping."
        case .pomOffset: "Show parallax UV displacement magnitude as a heatmap."
        case .ssaoBlurred: "Show the blurred screen-space ambient-occlusion texture."
        case .fxaaEdges: "Show edges detected by FXAA."
        case .smaaEdges: "Show edges detected by SMAA."
        case .smaaBlend: "Show the SMAA blend-weight texture."
        case .smaaDifference: "Show the difference introduced by SMAA."
        case .occlusion: "Show the lit scene with HZB-occluded bounds highlighted."
        case .preTonemapHDRLuminance: "Show scene luminance before tone mapping."
        case .postTonemapOutput: "Show the color pipeline's post-tone-map output."
        }
    }

    var engineMode: RenderDebugViewMode {
        switch self {
        case .lit: .lit
        case .albedo: .albedo
        case .normal: .normal
        case .position: .position
        case .depth: .depth
        case .roughness: .roughness
        case .metallic: .metallic
        case .height: .heightDebug
        case .pomOffset: .pomOffsetDebug
        case .ssaoBlurred: .ssaoBlurred
        case .fxaaEdges: .fxaaEdgeDebug
        case .smaaEdges: .smaaEdges
        case .smaaBlend: .smaaBlend
        case .smaaDifference: .smaaDifference
        case .occlusion: .occlusionDebug
        case .preTonemapHDRLuminance: .preTonemapHDRLuminance
        case .postTonemapOutput: .postTonemapOutput
        }
    }

    static var current: TextureDebugOption {
        get { allCases.first(where: { $0.engineMode == renderDebugViewMode }) ?? .lit }
        set { setRendering(.debugView(newValue.engineMode)) }
    }
}

/// The engine's non-render-target scene debug visualizations (`SpatialDebugVisualization`),
/// as View > Spatial Debug menu items, in menu order; a separator sits between groups. Unlike
/// the Showcase demo's HUD, there is no "Spatial Debug" master checkbox: that toggle is a
/// UI-only convenience in `DemoState` (it just forces Tile Bounds off when unchecked) with no
/// engine state of its own, so each switch here is independent, matching `SplatDebugOption`.
enum SpatialDebugOption: String, CaseIterable {
    case lodLevels
    case textureStreamingTiers
    case octreeLeafBounds
    case octreeLeafOccupiedOnly
    case tileBounds
    case staticBatchCellBounds

    enum Group: Int, CaseIterable {
        case coloring
        case octree
        case tiles
        case batching
    }

    var group: Group {
        switch self {
        case .lodLevels, .textureStreamingTiers: .coloring
        case .octreeLeafBounds, .octreeLeafOccupiedOnly: .octree
        case .tileBounds: .tiles
        case .staticBatchCellBounds: .batching
        }
    }

    var title: String {
        switch self {
        case .lodLevels: "LOD Debug"
        case .textureStreamingTiers: "Texture Streaming Debug"
        case .octreeLeafBounds: "Octree Cells"
        case .octreeLeafOccupiedOnly: "Occupied Only"
        case .tileBounds: "Tile Bounds"
        case .staticBatchCellBounds: "Static Batch Cell Bounds"
        }
    }

    var summary: String {
        switch self {
        case .lodLevels: "Tints every renderable by its currently active LOD level."
        case .textureStreamingTiers: "Tints every renderable by its current texture streaming tier: blue full, orange medium (capped), red minimum, yellow in-flight."
        case .octreeLeafBounds: "Draws the occupied octree's leaf-node bounds."
        case .octreeLeafOccupiedOnly: "Limits Octree Cells and Tile Bounds to leaves that hold something resident."
        case .tileBounds: "Draws streamed tile bounds, colored by each tile's load state (unloaded/parsing/parsed/HLOD/failed); follows Octree Cells' Leaf Color Mode and Occupied Only."
        case .staticBatchCellBounds: "Draws the static-batching grid's cell bounds."
        }
    }

    var isEnabled: Bool {
        get {
            let debug = SpatialDebugVisualization.shared
            return switch self {
            case .lodLevels: debug.colorRenderablesByLOD
            case .textureStreamingTiers: debug.colorRenderablesByStreamingTier
            case .octreeLeafBounds: debug.showOctreeLeafBounds
            case .octreeLeafOccupiedOnly: debug.octreeLeafOccupiedOnly
            case .tileBounds: debug.showTileBounds
            case .staticBatchCellBounds: debug.showStaticBatchCellBounds
            }
        }
        nonmutating set {
            let debug = SpatialDebugVisualization.shared
            switch self {
            case .lodLevels:
                setLODLevelDebug(enabled: newValue)
            case .textureStreamingTiers:
                setTextureStreamingTierDebug(enabled: newValue)
            case .octreeLeafBounds:
                // Re-supplies the other fields explicitly: the engine's own
                // `.octreeLeafBounds(.disabled)` convenience resets them to their defaults.
                setOctreeLeafBoundsDebug(
                    enabled: newValue,
                    maxLeafNodeCount: debug.maxLeafNodeCount,
                    occupiedOnly: debug.octreeLeafOccupiedOnly,
                    colorMode: debug.octreeLeafColorMode
                )
            case .octreeLeafOccupiedOnly:
                setOctreeLeafBoundsDebug(
                    enabled: debug.showOctreeLeafBounds,
                    maxLeafNodeCount: debug.maxLeafNodeCount,
                    occupiedOnly: newValue,
                    colorMode: debug.octreeLeafColorMode
                )
            case .tileBounds:
                setTileBoundsDebug(enabled: newValue, maxTileNodeCount: debug.maxTileNodeCount)
            case .staticBatchCellBounds:
                setStaticBatchCellBoundsDebug(
                    enabled: newValue,
                    maxCellCount: debug.maxStaticBatchCellCount,
                    colorMode: debug.staticBatchCellColorMode
                )
            }
        }
    }
}

/// Color mode for the View > Spatial Debug > Octree Cells > Leaf Color Mode radio items
/// (`SpatialDebugVisualization.octreeLeafColorMode`). Also governs Tile Bounds' coloring.
enum SpatialDebugLeafColorModeOption: String, CaseIterable {
    case plain
    case residency
    case culling

    var mode: SpatialDebugLeafColorMode {
        switch self {
        case .plain: .plain
        case .residency: .residency
        case .culling: .culling
        }
    }

    init(mode: SpatialDebugLeafColorMode) {
        switch mode {
        case .plain: self = .plain
        case .residency: self = .residency
        case .culling: self = .culling
        }
    }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .residency: "Residency"
        case .culling: "Culling"
        }
    }

    var summary: String {
        switch self {
        case .plain: "Every leaf draws in a single neutral color."
        case .residency: "Tints each leaf by what's resident inside it: green loaded, yellow loading, red unloaded, magenta a failed tile parse, orange mixed."
        case .culling: "Tints each leaf by whether the entities inside it were drawn this frame: green visible, blue culled, gray hidden, orange mixed. Tile Bounds shows a neutral wireframe in this mode; culling is octree-cell specific."
        }
    }

    /// The mode in effect.
    static var current: SpatialDebugLeafColorModeOption {
        get { SpatialDebugLeafColorModeOption(mode: SpatialDebugVisualization.shared.octreeLeafColorMode) }
        set {
            let debug = SpatialDebugVisualization.shared
            setOctreeLeafBoundsDebug(
                enabled: debug.showOctreeLeafBounds,
                maxLeafNodeCount: debug.maxLeafNodeCount,
                occupiedOnly: debug.octreeLeafOccupiedOnly,
                colorMode: newValue.mode
            )
        }
    }
}

/// Color mode for the View > Spatial Debug > Static Batch Cell Bounds > Cell Color Mode radio
/// items (`SpatialDebugVisualization.staticBatchCellColorMode`).
enum SpatialDebugBatchCellColorModeOption: String, CaseIterable {
    case plain
    case culling
    case lod
    case cell

    var mode: SpatialDebugBatchCellColorMode {
        switch self {
        case .plain: .plain
        case .culling: .culling
        case .lod: .lod
        case .cell: .cell
        }
    }

    init(mode: SpatialDebugBatchCellColorMode) {
        switch mode {
        case .plain: self = .plain
        case .culling: self = .culling
        case .lod: self = .lod
        case .cell: self = .cell
        }
    }

    var title: String {
        switch self {
        case .plain: "Plain"
        case .culling: "Culling"
        case .lod: "LOD"
        case .cell: "Cell"
        }
    }

    var summary: String {
        switch self {
        case .plain: "Every cell draws in a single neutral color."
        case .culling: "Tints each cell by whether its batched entities were drawn this frame: green visible, blue culled, orange mixed."
        case .lod: "Tints each cell by the LOD level its batch groups draw: red LOD 0, green LOD 1, blue LOD 2, orange mixed."
        case .cell: "Gives each cell a stable pseudo-random hue so neighboring cells are easy to tell apart."
        }
    }

    /// The mode in effect.
    static var current: SpatialDebugBatchCellColorModeOption {
        get { SpatialDebugBatchCellColorModeOption(mode: SpatialDebugVisualization.shared.staticBatchCellColorMode) }
        set {
            let debug = SpatialDebugVisualization.shared
            setStaticBatchCellBoundsDebug(
                enabled: debug.showStaticBatchCellBounds,
                maxCellCount: debug.maxStaticBatchCellCount,
                colorMode: newValue.mode
            )
        }
    }
}

/// The engine's Gaussian splat debug switches, as View > Splat Debug menu items, in menu
/// order; a separator sits between groups.
enum SplatDebugOption: String, CaseIterable {
    // The draw.
    case hzbOcclusionCull
    case opaqueDepthTest
    case antiAliasSplatPixels
    case toneMapSplatPixels
    case crispSplatKernel
    // Disk paging of a large .untoldgs (GaussianPageManager).
    case paging
    case forcePaging
    case freezePaging
    case residencyTint
    // Per-chunk coarse levels; the level mode itself is `SplatLevelModeOption`.
    case levelCrossFade
    case levelTint
    // Per-chunk wireframe bounds, colored by the level currently drawn.
    case chunkBounds
    // The working-set budget and the chunk stage it drives.
    case chunkCull
    case workingSetBudget
    case screenWeightedQuotas

    enum Group: Int, CaseIterable {
        case draw
        case paging
        case levels
        case bounds
        case budget
    }

    var group: Group {
        switch self {
        case .hzbOcclusionCull, .opaqueDepthTest, .antiAliasSplatPixels, .toneMapSplatPixels, .crispSplatKernel: .draw
        case .paging, .forcePaging, .freezePaging, .residencyTint: .paging
        case .levelCrossFade, .levelTint: .levels
        case .chunkBounds: .bounds
        case .chunkCull, .workingSetBudget, .screenWeightedQuotas: .budget
        }
    }

    var title: String {
        switch self {
        case .hzbOcclusionCull: "Disable Splat HZB Occlusion Cull"
        case .opaqueDepthTest: "Disable Splat Opaque Depth Test"
        case .antiAliasSplatPixels: "Anti-alias Splat Pixels"
        case .toneMapSplatPixels: "Tone-map Splat Pixels"
        case .crispSplatKernel: "Crisp Splat Kernel"
        case .paging: "Disable Splat Paging"
        case .forcePaging: "Force Splat Paging"
        case .freezePaging: "Freeze Splat Paging"
        case .residencyTint: "Tint Splats by Residency"
        case .levelCrossFade: "Disable Splat Level Cross-Fade"
        case .levelTint: "Tint Splats by Level"
        case .chunkBounds: "Show Splat Chunk Bounds"
        case .chunkCull: "Disable Splat Chunk Cull"
        case .workingSetBudget: "Disable Splat Working-Set Budget"
        case .screenWeightedQuotas: "Disable Splat Screen-Weighted Quotas"
        }
    }

    var summary: String {
        switch self {
        case .hzbOcclusionCull: "Splats are no longer culled against the previous frame's depth pyramid."
        case .opaqueDepthTest: "Splat fragments are no longer hidden behind meshes, gizmos or the grid."
        case .antiAliasSplatPixels: "FXAA and SMAA filter splat pixels like everything else, blurring their fine structure: the behaviour before the passes kept splat pixels as the splat pass blended them, for an A/B."
        case .toneMapSplatPixels: "The look pass grades and tone-maps splat pixels like everything else, lifting and flattening a capture that is a finished photograph already: the behaviour before the pass kept splat pixels as they came, for an A/B."
        case .crispSplatKernel: "Every splat is cut at 2√2 σ with its falloff renormalised to reach zero there, the kernel some viewers draw: about a fifth tighter than the trained Gaussian, crisper on fine texture such as asphalt, without the tails the reference blends. For an A/B against such a viewer."
        case .paging: "Every .untoldgs loads whole at its next load, whatever its size, instead of paging from disk through a pool: the pre-paging behaviour, for an A/B of what the pool costs and what its fill-in shows."
        case .forcePaging: "Every chunked .untoldgs pages from disk at its next load, whatever its size (the paging threshold is set to zero): a small capture then takes the paged path through a pool that holds it whole, so the fill-in, the residency tint and the demand-driven reads can be checked without a capture above the threshold. Disable Splat Paging wins when both are on."
        case .freezePaging: "Paged splats keep their resident set as it is: nothing is read, nothing is evicted, so the image is a function of the camera alone."
        case .residencyTint: "Every splat of a paged entity is tinted by its chunk's resident fraction: green whole, yellow deep, red head-only."
        case .levelCrossFade: "A chunk switches between its fine records and a coarse level at once instead of cross-fading over a few frames."
        case .levelTint: "Every splat of an entity with coarse levels is tinted by the level its chunk draws: white fine, yellow level 1, red level 2."
        case .chunkBounds: "Draws the bounding box of every chunk in a chunked .untoldgs asset, colored by the splat level currently drawn."
        case .chunkCull: "The chunk cull keeps every chunk of a .untoldgs, so the per-chunk pass walks the whole asset: an A/B of the chunk stage's cost."
        case .workingSetBudget: "The working set is sized to the resident splats instead of the budget and every visible chunk draws whole: the pre-budget behaviour, for an A/B of what the budget cuts."
        case .screenWeightedQuotas: "Every visible chunk is granted the same fraction of its splats instead of a quota weighted by its screen area: the pre-weighting rule, for an A/B of what the weighting moves."
        }
    }

    var isEnabled: Bool {
        get {
            let options = GaussianDebugOptions.shared
            return switch self {
            case .hzbOcclusionCull: options.disableHZBOcclusionCull
            case .opaqueDepthTest: options.disableOpaqueDepthTest
            case .antiAliasSplatPixels: options.antiAliasSplatPixels
            case .toneMapSplatPixels: options.toneMapSplatPixels
            case .crispSplatKernel: options.crispSplatKernel
            case .paging: options.disablePaging
            case .forcePaging: GaussianPagingPolicy.pagingThresholdBytesOverride == 0
            case .freezePaging: options.freezePaging
            case .residencyTint: options.residencyDebugTint
            case .levelCrossFade: options.disableLevelCrossFade
            case .levelTint: options.levelDebugTint
            case .chunkBounds: SpatialDebugVisualization.shared.showGaussianChunkBounds
            case .chunkCull: options.disableChunkCull
            case .workingSetBudget: options.disableWorkingSetBudget
            case .screenWeightedQuotas: options.disableScreenWeightedQuotas
            }
        }
        nonmutating set {
            let options = GaussianDebugOptions.shared
            switch self {
            case .hzbOcclusionCull: options.disableHZBOcclusionCull = newValue
            case .opaqueDepthTest: options.disableOpaqueDepthTest = newValue
            case .antiAliasSplatPixels: options.antiAliasSplatPixels = newValue
            case .toneMapSplatPixels: options.toneMapSplatPixels = newValue
            case .crispSplatKernel: options.crispSplatKernel = newValue
            case .paging: options.disablePaging = newValue
            case .forcePaging: GaussianPagingPolicy.pagingThresholdBytesOverride = newValue ? 0 : nil
            case .freezePaging: options.freezePaging = newValue
            case .residencyTint: options.residencyDebugTint = newValue
            case .levelCrossFade: options.disableLevelCrossFade = newValue
            case .levelTint: options.levelDebugTint = newValue
            case .chunkBounds:
                let debug = SpatialDebugVisualization.shared
                setGaussianChunkBoundsDebug(
                    enabled: newValue,
                    maxChunkCount: debug.maxGaussianChunkCount,
                    colorMode: .level
                )
            case .chunkCull: options.disableChunkCull = newValue
            case .workingSetBudget: options.disableWorkingSetBudget = newValue
            case .screenWeightedQuotas: options.disableScreenWeightedQuotas = newValue
            }
        }
    }
}

/// The splat fragment shader's per-pixel blend cap (`GaussianRuntimeLimits.maxBlendedSplatsPerPixel`)
/// as the View > Splat Debug > Splat Blend Cap radio items: the mobile figure, the Mac figure
/// and no cap, for an A/B of what the cap clips on a capture whose splats are mostly faint.
enum SplatBlendCapOption: String, CaseIterable {
    case mobile
    case mac
    case unlimited

    /// The override to install; nil restores the platform figure.
    var splats: Int? {
        switch self {
        case .mobile: GaussianRuntimeLimits.maxBlendedSplatsPerPixelMobile
        case .mac: GaussianRuntimeLimits.maxBlendedSplatsPerPixelMac
        case .unlimited: 255
        }
    }

    var title: String {
        switch self {
        case .mobile: "\(GaussianRuntimeLimits.maxBlendedSplatsPerPixelMobile) (Mobile Default)"
        case .mac: "\(GaussianRuntimeLimits.maxBlendedSplatsPerPixelMac) (Mac Default)"
        case .unlimited: "Unlimited"
        }
    }

    var summary: String {
        switch self {
        case .mobile: "The cap every platform had until 2026-09: a capture whose splats are mostly faint (a median opacity near 0.1 needs about 65 splats to saturate a pixel) is clipped."
        case .mac: "The Mac's cap: twice the mobile bound, enough for a faint capture; a capture that saturates early pays nothing more."
        case .unlimited: "Every sorted splat that reaches a pixel is blended (the shader counter's maximum, 255): the ground truth the caps approximate, at the cost of the longest blend chains."
        }
    }

    /// The choice in effect, read from the limit: the platform figure is the platform's
    /// choice, 255 is unlimited, any other override shows as the nearest.
    static var current: SplatBlendCapOption {
        get {
            let cap = GaussianRuntimeLimits.maxBlendedSplatsPerPixel
            if cap >= 255 { return .unlimited }
            return abs(cap - GaussianRuntimeLimits.maxBlendedSplatsPerPixelMobile) < abs(cap - GaussianRuntimeLimits.maxBlendedSplatsPerPixelMac) ? .mobile : .mac
        }
        set {
            GaussianDebugOptions.shared.disableBlendCap = false
            GaussianRuntimeLimits.maxBlendedSplatsPerPixelOverride = newValue.splats
        }
    }
}

/// How a `.untoldgs` entity with per-chunk coarse levels chooses each chunk's level
/// (`GaussianDebugOptions.gaussianLevelMode`), as the View > Splat Debug > Level Mode radio
/// items.
enum SplatLevelModeOption: String, CaseIterable {
    case auto
    case fineOnly
    case coarseOnly

    var mode: GaussianLevelMode {
        switch self {
        case .auto: .auto
        case .fineOnly: .fineOnly
        case .coarseOnly: .coarseOnly
        }
    }

    init(mode: GaussianLevelMode) {
        switch mode {
        case .auto: self = .auto
        case .fineOnly: self = .fineOnly
        case .coarseOnly: self = .coarseOnly
        }
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .fineOnly: "Fine Only"
        case .coarseOnly: "Coarse Only"
        }
    }

    var summary: String {
        switch self {
        case .auto: "The level rule: a far or not-yet-paged chunk draws a merged coarse level, the rest draw their fine records."
        case .fineOnly: "Every chunk draws its fine records only: byte for byte the frame of a file without a coarse section, the A/B of what the levels change."
        case .coarseOnly: "Every chunk draws its coarsest available level."
        }
    }

    /// The mode in effect.
    static var current: SplatLevelModeOption {
        get { SplatLevelModeOption(mode: GaussianDebugOptions.shared.gaussianLevelMode) }
        set { GaussianDebugOptions.shared.gaussianLevelMode = newValue.mode }
    }
}
