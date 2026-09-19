//
//  EditorDockLayout.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import Combine
import CoreGraphics
import Foundation

/// The docking layout of the editor window: three areas around the viewport,
/// left, right and bottom, each showing its panels as tabs. A panel dropped on
/// an area joins it; the viewport stays in the centre. The mockup's arrangement
/// is the default: hierarchy left at 250, the dock panels below at 250, the
/// inspector right at 320.
///
/// Pure Swift, no SwiftUI: every rule here is unit-tested. The shared instance
/// is what the window renders and what the menu bar toggles.
final class EditorDockLayout: ObservableObject {
    static let shared = EditorDockLayout(defaults: .standard)

    static let defaultsKey = "editor.layout.v2"
    static let formatVersion = 2

    /// The areas the window renders.
    @Published private(set) var state: DockLayoutState
    /// The panel a tab drag carries, from the drag's start to its drop.
    @Published private(set) var draggingPanel: PanelID?

    /// Where each closed panel was, so reopening it puts it back.
    private var lastAreas: [PanelID: DockArea] = [:]
    /// The tabs hidden together by an area toggle (⌘2), reopened together, and
    /// the one that was in front.
    private var collapsedAreas: [DockArea: [PanelID]] = [:]
    private var collapsedFronts: [DockArea: PanelID] = [:]
    /// The layout before Focus Viewport, restored by the next toggle.
    private var focusSaved: DockLayoutState?
    private let defaults: UserDefaults?

    /// A layout persisted in `defaults`, or the default layout when nothing
    /// valid is stored. Pass `nil` for a layout that is never persisted.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        if let defaults, let stored = Self.load(from: defaults) {
            state = stored.state
            lastAreas = stored.lastAreas
        } else {
            state = Self.defaultState()
        }
    }

    convenience init() {
        self.init(defaults: nil)
    }

    // MARK: - Queries

    var openPanels: [PanelID] {
        state.panels
    }

    func isOpen(_ panel: PanelID) -> Bool {
        panel == .viewport || state.panels.contains(panel)
    }

    func area(of panel: PanelID) -> DockArea? {
        state.area(of: panel)
    }

    func tabs(in area: DockArea) -> [PanelID] {
        state[area].tabs
    }

    func isVisible(_ area: DockArea) -> Bool {
        state[area].isVisible
    }

    var isFocusedOnViewport: Bool {
        focusSaved != nil
    }

    // MARK: - Tabs

    func select(_ panel: PanelID) {
        guard let area = area(of: panel), state[area].selected != panel else { return }
        state[area].selected = panel
        persist()
    }

    func close(_ panel: PanelID) {
        guard panel.canClose, let area = area(of: panel) else { return }
        lastAreas[panel] = area
        remove(panel, from: area)
        persist()
    }

    /// Opens a closed panel where it was last, else in its default area, and
    /// brings it to front.
    func open(_ panel: PanelID) {
        guard let destination = lastAreas[panel] ?? panel.defaultArea else { return }
        if isOpen(panel) {
            select(panel)
            return
        }
        append(panel, to: destination)
        persist()
    }

    func toggle(_ panel: PanelID) {
        if isOpen(panel) {
            close(panel)
        } else {
            open(panel)
        }
    }

    /// Hides or shows a whole area, as ⌘2 does for the bottom one: hiding
    /// remembers its tabs, showing brings them back with the same one in front.
    func toggleArea(_ area: DockArea) {
        if state[area].isVisible {
            let tabs = state[area].tabs
            collapsedAreas[area] = tabs
            collapsedFronts[area] = state[area].selected
            for panel in tabs {
                lastAreas[panel] = area
            }
            state[area].tabs = []
            state[area].selected = nil
        } else {
            let tabs = collapsedAreas[area] ?? PanelID.available.filter { $0.defaultArea == area }
            for panel in tabs where isOpen(panel) == false {
                append(panel, to: area)
            }
            let front = collapsedFronts[area].flatMap { state[area].tabs.contains($0) ? $0 : nil }
            state[area].selected = front ?? state[area].tabs.first
        }
        persist()
    }

    // MARK: - Moving

    /// Moves a panel into an area, as the last tab and in front; a panel already
    /// there just comes to front.
    func move(_ panel: PanelID, to destination: DockArea) {
        guard panel.isDockable else { return }
        if let current = area(of: panel) {
            if current == destination {
                select(panel)
                return
            }
            remove(panel, from: current)
        }
        append(panel, to: destination)
        lastAreas[panel] = destination
        persist()
    }

    func beginDrag(of panel: PanelID) {
        draggingPanel = panel
    }

    func endDrag() {
        draggingPanel = nil
    }

    // MARK: - Resizing

    /// The length an area may take for what a drag asks: no less than the
    /// minimum of its tabs, no more than `maximum` (the room that leaves the
    /// viewport its minimum), the minimum winning when the two conflict. What a
    /// drag shows before the mouse goes up, and what `resize` then applies.
    func clampedLength(for area: DockArea, proposed: CGFloat, maximum: CGFloat) -> CGFloat {
        let minimum = DockLayoutGeometry.minimumLength(of: state[area].tabs, in: area)
        return min(max(proposed, minimum), max(minimum, maximum))
    }

    /// Sets an area's length from a divider drag: the length it is laid out at
    /// plus the drag, clamped as `clampedLength` does. The layout persists when
    /// the drag ends.
    func resize(_ area: DockArea, delta: CGFloat, currentLength: CGFloat, maximum: CGFloat) {
        state[area].length = clampedLength(for: area, proposed: currentLength + delta, maximum: maximum)
    }

    func resizeEnded() {
        persist()
    }

    // MARK: - Whole-layout

    /// Collapses the layout to the viewport, or restores what was there.
    func toggleFocusViewport() {
        if let saved = focusSaved {
            focusSaved = nil
            state = saved
        } else {
            focusSaved = state
            for area in DockArea.allCases {
                state[area].tabs = []
                state[area].selected = nil
            }
        }
    }

    func reset() {
        focusSaved = nil
        lastAreas = [:]
        collapsedAreas = [:]
        collapsedFronts = [:]
        state = Self.defaultState()
        persist()
    }

    /// The mockup's layout.
    static func defaultState() -> DockLayoutState {
        DockLayoutState(
            left: DockAreaState(tabs: [.hierarchy], length: DockArea.left.defaultLength),
            right: DockAreaState(tabs: [.inspector], length: DockArea.right.defaultLength),
            bottom: DockAreaState(
                tabs: PanelID.available.filter { $0.defaultArea == .bottom },
                selected: .assets,
                length: DockArea.bottom.defaultLength
            )
        )
    }

    // MARK: - Editing

    private func append(_ panel: PanelID, to area: DockArea) {
        guard state[area].tabs.contains(panel) == false else {
            state[area].selected = panel
            return
        }
        state[area].tabs.append(panel)
        state[area].selected = panel
    }

    private func remove(_ panel: PanelID, from area: DockArea) {
        state[area].tabs.removeAll { $0 == panel }
        if state[area].selected == panel {
            state[area].selected = state[area].tabs.first
        }
    }

    // MARK: - Persistence

    private struct Snapshot: Codable {
        var version: Int
        var state: DockLayoutState
        var lastAreas: [String: DockArea]
    }

    private func persist() {
        guard let defaults else { return }
        let snapshot = Snapshot(
            version: Self.formatVersion,
            state: focusSaved ?? state,
            lastAreas: Dictionary(uniqueKeysWithValues: lastAreas.map { ($0.key.rawValue, $0.value) })
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> (state: DockLayoutState, lastAreas: [PanelID: DockArea])? {
        guard let data = defaults.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == formatVersion,
              isValid(snapshot.state)
        else {
            return nil
        }
        var state = snapshot.state
        for area in DockArea.allCases where state[area].selected == nil {
            state[area].selected = state[area].tabs.first
        }
        var lastAreas: [PanelID: DockArea] = [:]
        for (raw, area) in snapshot.lastAreas {
            if let panel = PanelID(rawValue: raw) {
                lastAreas[panel] = area
            }
        }
        return (state, lastAreas)
    }

    /// A layout the window can render: every docked panel once, all of them
    /// dockable and available in this build, a front tab that exists, and
    /// positive lengths.
    static func isValid(_ state: DockLayoutState) -> Bool {
        let panels = state.panels
        guard Set(panels).count == panels.count,
              panels.allSatisfy(\.isDockable),
              Set(panels).isSubset(of: PanelID.available)
        else {
            return false
        }
        return DockArea.allCases.allSatisfy { area in
            let areaState = state[area]
            let frontExists = areaState.selected.map { areaState.tabs.contains($0) } ?? true
            return frontExists && areaState.length > 0
        }
    }
}
