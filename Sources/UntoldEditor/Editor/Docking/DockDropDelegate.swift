//
//  DockDropDelegate.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UniformTypeIdentifiers

/// Receives a dragged tab: over an area it means "join this area"; over the
/// viewport the edge under the pointer picks the area. It keeps the highlighted
/// area up to date while the drag hovers and moves the panel on drop. A tab
/// drag carries the panel id as a property list, a type no other drop target of
/// the editor accepts (entity rows take text, asset rows JSON), so nothing else
/// lights up for it.
struct DockDropDelegate: DropDelegate {
    enum Target {
        case area(DockArea)
        case viewport
    }

    static let dragType = UTType.propertyList

    let target: Target
    let size: CGSize
    let layout: EditorDockLayout
    @Binding var highlightedArea: DockArea?

    /// The item a tab drag carries.
    static func itemProvider(for panel: PanelID) -> NSItemProvider {
        let data = (try? PropertyListSerialization.data(fromPropertyList: panel.rawValue, format: .xml, options: 0)) ?? Data()
        return NSItemProvider(item: data as NSData, typeIdentifier: dragType.identifier)
    }

    /// The panel a dropped item carries, if it is a tab drag.
    static func panel(from data: Data) -> PanelID? {
        guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? String else {
            return nil
        }
        return PanelID(rawValue: raw)
    }

    private func area(for info: DropInfo) -> DockArea? {
        switch target {
        case let .area(area):
            return area
        case .viewport:
            return DockLayoutGeometry.dropArea(at: info.location, in: size)
        }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [Self.dragType])
    }

    func dropEntered(info: DropInfo) {
        highlightedArea = area(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let area = area(for: info)
        highlightedArea = area
        return DropProposal(operation: area == nil ? .cancel : .move)
    }

    func dropExited(info _: DropInfo) {
        highlightedArea = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let destination = area(for: info)
        highlightedArea = nil
        guard let destination else {
            layout.endDrag()
            return false
        }
        if let panel = layout.draggingPanel {
            layout.endDrag()
            layout.move(panel, to: destination)
            return true
        }
        guard let provider = info.itemProviders(for: [Self.dragType]).first else {
            return false
        }
        let layout = layout
        provider.loadDataRepresentation(forTypeIdentifier: Self.dragType.identifier) { data, _ in
            guard let data, let panel = Self.panel(from: data) else { return }
            DispatchQueue.main.async {
                layout.move(panel, to: destination)
            }
        }
        return true
    }
}
