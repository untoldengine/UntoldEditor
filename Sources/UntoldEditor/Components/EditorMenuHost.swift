//
//  EditorMenuHost.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import AppKit
import UntoldComponentKit

/// Builds the menu items that loaded `EditorMenuPlugin`s declare with `@UntoldMenu`, and keeps
/// their checkmarks in step with the wrapped values.
///
/// Items always land under one of the editor's fixed roots. `File` and `View` are the editor's
/// own menus, where contributed items follow a separator; `Debug` and `Tools` are created here
/// and exist only while they hold something. Everything this class adds is tracked, so a
/// reload removes exactly what the previous revision contributed.
final class EditorMenuHost: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let shared = EditorMenuHost(mainMenuProvider: { NSApp?.mainMenu })

    /// What a contributed `NSMenuItem` stands for.
    final class Binding: NSObject {
        weak var owner: EditorMenuPlugin?
        let menu: AnyUntoldMenu
        /// Set on the items of a choice submenu.
        let choiceRawValue: String?

        init(owner: EditorMenuPlugin, menu: AnyUntoldMenu, choiceRawValue: String? = nil) {
            self.owner = owner
            self.menu = menu
            self.choiceRawValue = choiceRawValue
        }
    }

    /// Called after the user changed a toggle or a choice, once the wrapper holds the new value.
    var onValueChanged: ((EditorMenuPlugin, AnyUntoldMenu) -> Void)?

    private let mainMenuProvider: () -> NSMenu?
    private var addedItems: [NSMenuItem] = []
    private var createdRootItems: [NSMenuItem] = []
    private var adoptedDelegates: [NSMenu] = []
    private var submenus: [String: NSMenu] = [:]
    private var separatedRoots: Set<UntoldMenuDomain> = []

    init(mainMenuProvider: @escaping () -> NSMenu?) {
        self.mainMenuProvider = mainMenuProvider
    }

    // MARK: Building

    func install(_ entries: [(owner: EditorMenuPlugin, menu: AnyUntoldMenu)]) {
        for entry in entries {
            guard let root = rootMenu(for: entry.menu.domain) else { continue }
            let parent = submenu(for: entry.menu.submenuPath, domain: entry.menu.domain, root: root)
            add(makeItem(owner: entry.owner, menu: entry.menu), to: parent)
        }
    }

    /// Removes everything this host added, leaving the editor's own menus as they were.
    func removeAll() {
        for item in addedItems {
            item.menu?.removeItem(item)
        }
        for item in createdRootItems {
            item.menu?.removeItem(item)
        }
        for menu in adoptedDelegates where menu.delegate === self {
            menu.delegate = nil
        }
        addedItems.removeAll()
        createdRootItems.removeAll()
        adoptedDelegates.removeAll()
        submenus.removeAll()
        separatedRoots.removeAll()
    }

    private func rootMenu(for domain: UntoldMenuDomain) -> NSMenu? {
        guard let mainMenu = mainMenuProvider() else { return nil }
        if let existing = mainMenu.items.first(where: { $0.submenu?.title == domain.rootTitle })?.submenu {
            if separatedRoots.contains(domain) == false, createdRootItems.contains(where: { $0.submenu === existing }) == false {
                // One of the editor's own menus: set contributed items apart, once.
                separatedRoots.insert(domain)
                let separator = NSMenuItem.separator()
                existing.addItem(separator)
                addedItems.append(separator)
                if existing.delegate == nil {
                    existing.delegate = self
                    adoptedDelegates.append(existing)
                }
            }
            return existing
        }

        switch domain {
        case .file, .view:
            return nil // the editor always has these; without them there is nowhere to put the item
        case .debug, .tools:
            let menu = NSMenu(title: domain.rootTitle)
            menu.autoenablesItems = false
            menu.delegate = self
            let item = NSMenuItem(title: domain.rootTitle, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.addItem(item)
            createdRootItems.append(item)
            return menu
        }
    }

    /// Finds or creates the nested submenus for `path`. Only submenus created here are reused,
    /// so a contributed item never lands inside one of the editor's own submenus.
    private func submenu(for path: [String], domain: UntoldMenuDomain, root: NSMenu) -> NSMenu {
        var parent = root
        var key = domain.rawValue
        for segment in path {
            key += "/" + segment
            if let existing = submenus[key] {
                parent = existing
                continue
            }
            let menu = NSMenu(title: segment)
            menu.autoenablesItems = false
            menu.delegate = self
            let item = NSMenuItem(title: segment, action: nil, keyEquivalent: "")
            item.submenu = menu
            add(item, to: parent)
            submenus[key] = menu
            parent = menu
        }
        return parent
    }

    private func makeItem(owner: EditorMenuPlugin, menu: AnyUntoldMenu) -> NSMenuItem {
        switch menu.kind {
        case .toggle, .action:
            let item = NSMenuItem(title: menu.title, action: #selector(itemClicked(_:)), keyEquivalent: menu.keyEquivalent)
            item.target = self
            item.representedObject = Binding(owner: owner, menu: menu)
            item.toolTip = menu.tooltip
            return item

        case let .choice(choices):
            let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
            item.representedObject = Binding(owner: owner, menu: menu)
            item.toolTip = menu.tooltip
            let choiceMenu = NSMenu(title: menu.title)
            choiceMenu.autoenablesItems = false
            choiceMenu.delegate = self
            for choice in choices {
                let choiceItem = NSMenuItem(title: choice.title, action: #selector(itemClicked(_:)), keyEquivalent: "")
                choiceItem.target = self
                choiceItem.representedObject = Binding(owner: owner, menu: menu, choiceRawValue: choice.rawValue)
                choiceMenu.addItem(choiceItem)
            }
            item.submenu = choiceMenu
            return item
        }
    }

    private func add(_ item: NSMenuItem, to menu: NSMenu) {
        menu.addItem(item)
        addedItems.append(item)
    }

    // MARK: Opening and clicking

    /// Also forwarded by the app delegate for the `View` menu, whose delegate it is.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let bindings = menu.items.compactMap { $0.representedObject as? Binding }
        var asked: [ObjectIdentifier] = []
        for binding in bindings {
            guard let owner = binding.owner, asked.contains(ObjectIdentifier(owner)) == false else { continue }
            asked.append(ObjectIdentifier(owner))
            owner.menuWillOpen()
        }
        for item in menu.items {
            guard let binding = item.representedObject as? Binding else { continue }
            item.isEnabled = binding.owner != nil && binding.menu.isEnabled
            item.state = Self.state(for: binding)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let binding = menuItem.representedObject as? Binding else { return true }
        return binding.owner != nil && binding.menu.isEnabled
    }

    static func state(for binding: Binding) -> NSControl.StateValue {
        switch (binding.menu.kind, binding.menu.menuValue) {
        case (.toggle, .bool(true)):
            return .on
        case let (.choice, .choice(current)):
            return binding.choiceRawValue == current ? .on : .off
        default:
            return .off
        }
    }

    @objc func itemClicked(_ sender: NSMenuItem) {
        guard let binding = sender.representedObject as? Binding, let owner = binding.owner else { return }
        switch binding.menu.kind {
        case .action:
            binding.menu.perform(owner: owner)
            return
        case .toggle:
            let isOn = binding.menu.menuValue == .bool(true)
            guard binding.menu.setMenuValue(.bool(!isOn)) else { return }
        case .choice:
            guard let rawValue = binding.choiceRawValue, binding.menu.setMenuValue(.choice(rawValue)) else { return }
        }
        onValueChanged?(owner, binding.menu)
    }
}
