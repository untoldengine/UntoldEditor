//
//  CodeComponentsTestSupport.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import Foundation
import UntoldComponentKit
@testable import UntoldEditor
import XCTest

/// A scratch directory that removes itself.
final class ScratchDirectory {
    let url: URL

    init(_ name: String = "ComponentPluginsTests") throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ contents: String, to relativePath: String) throws -> URL {
        let file = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func directory(_ relativePath: String) throws -> URL {
        let directory = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

func makeTestSDK(providedModules: [String] = ["UntoldComponentKit", "UntoldEngine"]) -> ComponentSDK {
    ComponentSDK(
        modulesDirectory: URL(fileURLWithPath: "/sdk/Modules"),
        cShaderTypesModuleMap: URL(fileURLWithPath: "/sdk/CShaderTypes/module.modulemap"),
        providedModules: providedModules,
        targetTriple: "arm64-apple-macosx14.0",
        recordedCompilerVersion: nil,
        engineURL: nil,
        engineRevision: nil,
        isBundled: false
    )
}

/// A main menu shaped like the editor's: an app menu, File and View.
func makeEditorLikeMainMenu() -> NSMenu {
    let mainMenu = NSMenu()
    for title in ["App", "File", "View"] {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.addItem(NSMenuItem(title: "\(title) built-in", action: nil, keyEquivalent: ""))
        item.submenu = menu
        mainMenu.addItem(item)
    }
    return mainMenu
}

final class MenuProbeExtension: EditorMenuPlugin {
    enum Quality: String, CaseIterable { case low, high }

    @UntoldMenu(.view, "Preview Twins") var preview = true
    @UntoldMenu(.debug, "Splat Twin/Quality") var quality: Quality = .low
    @UntoldMenu(.debug, "Splat Twin/Reset") var reset = UntoldMenuAction { (owner: EditorMenuPlugin) in
        (owner as? MenuProbeExtension)?.events.append("reset")
    }

    @UntoldMenu(.tools, "Bake", persist: false) var bake = false

    var events: [String] = []
    var externalPreviewState: Bool?

    override func onLoad() {
        events.append("load")
    }

    override func onUnload() {
        events.append("unload")
    }

    override func onSceneReset() {
        events.append("sceneReset")
    }

    override func onPlayModeChanged(_ isPlaying: Bool) {
        events.append("play:\(isPlaying)")
    }

    override func menuDidChange(_ domain: UntoldMenuDomain, _ path: String) {
        events.append("changed:\(domain.rawValue)/\(path)")
    }

    override func menuWillOpen() {
        events.append("willOpen")
        if let externalPreviewState {
            preview = externalPreviewState
        }
    }
}

final class ClashingExtension: EditorMenuPlugin {
    @UntoldMenu(.view, "Preview Twins") var alsoPreview = false
    @UntoldMenu(.debug, " / ") var untitled = false
    @UntoldMenu(.tools, "Unique") var unique = false
}
