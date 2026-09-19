//
//  DockContainerView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI

/// Renders the docking layout between the toolbar and the status bar: the left
/// area, the viewport with the bottom area under it, the right area, and a
/// divider between each area and the viewport. An area with no panels leaves a
/// thin edge strip to drop a tab on. A tab dragged over the viewport docks into
/// the area of the edge it is dropped on. In explore mode only the viewport
/// shows, whatever the layout holds.
struct DockContainerView: View {
    @ObservedObject var layout: EditorDockLayout
    let registry: EditorPanelRegistry
    var viewportOnly = false
    /// The render loop holds while a divider drags, as it does during a window resize.
    var onResizeBegan: () -> Void = {}
    var onResizeEnded: () -> Void = {}

    @State private var viewportDropArea: DockArea?

    var body: some View {
        GeometryReader { proxy in
            content(in: proxy.size)
        }
        .clipped()
    }

    private func content(in size: CGSize) -> some View {
        let state = layout.state
        let showsLeft = viewportOnly == false && state.left.isVisible
        let showsRight = viewportOnly == false && state.right.isVisible
        let showsBottom = viewportOnly == false && state.bottom.isVisible
        let divider = DockLayoutGeometry.dividerThickness
        let edge = viewportOnly ? 0 : DockLayoutGeometry.edgeTargetThickness
        let widths = DockLayoutGeometry.sideWidths(
            left: showsLeft ? state.left.length : nil,
            leftMinimum: DockLayoutGeometry.minimumLength(of: state.left.tabs, in: .left),
            right: showsRight ? state.right.length : nil,
            rightMinimum: DockLayoutGeometry.minimumLength(of: state.right.tabs, in: .right),
            total: size.width - (showsLeft ? 0 : edge) - (showsRight ? 0 : edge)
        )
        let bottomHeight = DockLayoutGeometry.bottomHeight(
            showsBottom ? state.bottom.length : nil,
            minimum: DockLayoutGeometry.minimumLength(of: state.bottom.tabs, in: .bottom),
            total: size.height - (showsBottom ? 0 : edge)
        )
        let leftSpace = showsLeft ? widths.left + divider : edge
        let rightSpace = showsRight ? widths.right + divider : edge
        let bottomSpace = showsBottom ? bottomHeight + divider : edge
        let centerWidth = max(0, size.width - leftSpace - rightSpace)
        let viewportHeight = max(0, size.height - bottomSpace)
        let viewportSize = CGSize(width: centerWidth, height: viewportHeight)

        return HStack(spacing: 0) {
            if showsLeft {
                DockGroupView(area: .left, size: CGSize(width: widths.left, height: size.height), layout: layout, registry: registry)
                    .frame(width: widths.left, height: size.height)
                EditorSplitDivider(
                    orientation: .vertical,
                    onDragBegan: onResizeBegan,
                    onDrag: { delta in
                        layout.resize(.left, delta: delta, currentLength: widths.left, maximum: DockLayoutGeometry.maximumLength(for: .left, in: size, otherSide: widths.right))
                    },
                    onDragEnded: endResize
                )
            } else if viewportOnly == false {
                DockEdgeTarget(area: .left, layout: layout)
                    .frame(width: edge, height: size.height)
            }
            VStack(spacing: 0) {
                registry.content(.viewport)
                    .frame(width: centerWidth, height: viewportHeight)
                    .clipped()
                    .overlay {
                        DockDropZoneHighlight(rect: viewportDropArea.map { DockLayoutGeometry.viewportDropZoneRect(for: $0, in: viewportSize) })
                    }
                    .onDrop(
                        of: [DockDropDelegate.dragType],
                        delegate: DockDropDelegate(target: .viewport, size: viewportSize, layout: layout, highlightedArea: $viewportDropArea)
                    )
                if showsBottom {
                    EditorSplitDivider(
                        orientation: .horizontal,
                        onDragBegan: onResizeBegan,
                        onDrag: { delta in
                            layout.resize(.bottom, delta: -delta, currentLength: bottomHeight, maximum: DockLayoutGeometry.maximumLength(for: .bottom, in: size))
                        },
                        onDragEnded: endResize
                    )
                    DockGroupView(area: .bottom, size: CGSize(width: centerWidth, height: bottomHeight), layout: layout, registry: registry)
                        .frame(width: centerWidth, height: bottomHeight)
                } else if viewportOnly == false {
                    DockEdgeTarget(area: .bottom, layout: layout)
                        .frame(width: centerWidth, height: edge)
                }
            }
            .frame(width: centerWidth, height: size.height)
            if showsRight {
                EditorSplitDivider(
                    orientation: .vertical,
                    onDragBegan: onResizeBegan,
                    onDrag: { delta in
                        layout.resize(.right, delta: -delta, currentLength: widths.right, maximum: DockLayoutGeometry.maximumLength(for: .right, in: size, otherSide: widths.left))
                    },
                    onDragEnded: endResize
                )
                DockGroupView(area: .right, size: CGSize(width: widths.right, height: size.height), layout: layout, registry: registry)
                    .frame(width: widths.right, height: size.height)
            } else if viewportOnly == false {
                DockEdgeTarget(area: .right, layout: layout)
                    .frame(width: edge, height: size.height)
            }
        }
    }

    private func endResize() {
        layout.resizeEnded()
        onResizeEnded()
    }
}
