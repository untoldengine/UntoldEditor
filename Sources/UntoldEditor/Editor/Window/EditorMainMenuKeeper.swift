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

/// Keeps the editor's menus in the menu bar. The editor is a SwiftUI `App`,
/// for the space the Apple Vision Pro preview shows, with its menus built by
/// its AppKit delegate. SwiftUI installs a menu bar of its own, from its
/// default commands, and on macOS 26 it does so after the delegate has set
/// the editor's, and again whenever it updates: the bar then reads Edit,
/// View, Window and Help, without the editor's File menu and View items.
///
/// The keeper does not fight over which `NSMenu` is the main menu: it moves
/// the editor's menus into whatever menu bar is installed and takes that
/// bar's own items out, so SwiftUI keeps the object it installed and the
/// user sees the editor's menus. It looks again whenever the main menu
/// changes and after every event the application handles. Made and used on
/// the main thread, where AppKit sets the menu bar.
final class EditorMainMenuKeeper: @unchecked Sendable {
    /// The editor's menus, in order: the app menu first.
    let items: [NSMenuItem]
    /// The editor's Window menu, which lists the open windows.
    let windowsMenu: NSMenu?
    /// How many times the editor's menus were put back; for the tests and the log.
    private(set) var restorations = 0
    private let application: NSApplication
    private var observation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var checkIsScheduled = false

    init(menu: NSMenu, windowsMenu: NSMenu? = nil, application: NSApplication = .shared) {
        items = menu.items
        self.windowsMenu = windowsMenu
        self.application = application
        install(into: application.mainMenu ?? menu)
        observation = application.observe(\.mainMenu, options: [.new]) { [weak self] _, _ in
            self?.scheduleCheck()
        }
        let center = NotificationCenter.default
        for name in [NSApplication.didUpdateNotification, NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.checkNow()
            })
        }
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// True while the menu bar shows the editor's menus and nothing else.
    var isInPlace: Bool {
        guard let bar = application.mainMenu else { return false }
        return bar.items.count == items.count && zip(bar.items, items).allSatisfy { $0 === $1 }
    }

    /// Outside the setter that is replacing the menu bar.
    private func scheduleCheck() {
        guard checkIsScheduled == false else { return }
        checkIsScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.checkIsScheduled = false
            self?.checkNow()
        }
    }

    /// Puts the editor's menus back when the menu bar shows something else.
    func checkNow() {
        guard isInPlace == false else { return }
        restorations += 1
        if restorations == 1 {
            Logger.log(message: "The menu bar was replaced; the editor's menus are put back.")
        }
        install(into: application.mainMenu ?? NSMenu())
    }

    /// Makes `bar` the menu bar, with the editor's menus and nothing else.
    private func install(into bar: NSMenu) {
        // A menu bar of SwiftUI's fills itself in through its delegate.
        bar.delegate = nil
        for item in items {
            item.menu?.removeItem(item)
        }
        bar.removeAllItems()
        for item in items {
            bar.addItem(item)
        }
        if application.mainMenu !== bar {
            application.mainMenu = bar
        }
        if let windowsMenu, application.windowsMenu !== windowsMenu {
            application.windowsMenu = windowsMenu
        }
    }
}
