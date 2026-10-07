//
//  EditorMainMenuKeeper.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import UntoldEngine

/// Keeps the editor's menu bar in place. The editor is a SwiftUI `App`, for
/// the space the Apple Vision Pro preview shows, with its menus built by its
/// AppKit delegate. SwiftUI installs a menu bar of its own, from its default
/// commands, and on macOS 26 it does so after the delegate has set the
/// editor's: the bar then reads Edit, View, Window and Help, without the
/// editor's File menu and View items. The keeper installs the editor's menu
/// and puts it back whenever something else replaces it. Made and used on
/// the main thread, where AppKit sets the menu bar.
final class EditorMainMenuKeeper: @unchecked Sendable {
    /// The editor's menu bar.
    let menu: NSMenu
    /// How many times another menu was put aside; for the tests and the log.
    private(set) var restorations = 0
    private let application: NSApplication
    private var observation: NSKeyValueObservation?

    init(menu: NSMenu, application: NSApplication = .shared) {
        self.menu = menu
        self.application = application
        application.mainMenu = menu
        observation = application.observe(\.mainMenu, options: [.new]) { [weak self] application, _ in
            guard let self, application.mainMenu !== menu else { return }
            // Outside the setter that is replacing it.
            DispatchQueue.main.async {
                self.restore()
            }
        }
    }

    private func restore() {
        guard application.mainMenu !== menu else { return }
        restorations += 1
        if restorations == 1 {
            Logger.log(message: "The menu bar was replaced; the editor's is put back.")
        }
        application.mainMenu = menu
    }
}
