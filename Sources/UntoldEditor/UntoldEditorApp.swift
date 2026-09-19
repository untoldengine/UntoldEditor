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
        window.isMovableByWindowBackground = true
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
    // The working-set budget and the chunk stage it drives.
    case chunkCull
    case workingSetBudget
    case screenWeightedQuotas

    enum Group: Int, CaseIterable {
        case draw
        case paging
        case levels
        case budget
    }

    var group: Group {
        switch self {
        case .hzbOcclusionCull, .opaqueDepthTest, .antiAliasSplatPixels, .toneMapSplatPixels, .crispSplatKernel: .draw
        case .paging, .forcePaging, .freezePaging, .residencyTint: .paging
        case .levelCrossFade, .levelTint: .levels
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
