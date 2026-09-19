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
/// the area of the edge it is dropped on. A divider drag draws a line where the
/// divider will land and resizes once the mouse goes up, so the viewport and
/// the panels are laid out once, at the final size. In explore mode only the
/// viewport shows, whatever the layout holds.
struct DockContainerView: View {
    @ObservedObject var layout: EditorDockLayout
    let registry: EditorPanelRegistry
    var viewportOnly = false

    @State private var viewportDropArea: DockArea?
    @State private var resizePreview: DockResizePreview?

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
                areaDivider(for: .left, currentLength: widths.left, maximum: DockLayoutGeometry.maximumLength(for: .left, in: size, otherSide: widths.right))
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
                    areaDivider(for: .bottom, currentLength: bottomHeight, maximum: DockLayoutGeometry.maximumLength(for: .bottom, in: size))
                    DockGroupView(area: .bottom, size: CGSize(width: centerWidth, height: bottomHeight), layout: layout, registry: registry)
                        .frame(width: centerWidth, height: bottomHeight)
                } else if viewportOnly == false {
                    DockEdgeTarget(area: .bottom, layout: layout)
                        .frame(width: centerWidth, height: edge)
                }
            }
            .frame(width: centerWidth, height: size.height)
            if showsRight {
                areaDivider(for: .right, currentLength: widths.right, maximum: DockLayoutGeometry.maximumLength(for: .right, in: size, otherSide: widths.left))
                DockGroupView(area: .right, size: CGSize(width: widths.right, height: size.height), layout: layout, registry: registry)
                    .frame(width: widths.right, height: size.height)
            } else if viewportOnly == false {
                DockEdgeTarget(area: .right, layout: layout)
                    .frame(width: edge, height: size.height)
            }
        }
        .overlay {
            DockResizePreviewLine(rect: resizePreview.map {
                DockLayoutGeometry.resizePreviewRect(for: $0.area, length: $0.length, leftSpace: leftSpace, rightSpace: rightSpace, in: size)
            })
        }
    }

    /// The divider between an area and the viewport. While it drags, the area's
    /// length follows the pointer as a line only; the layout takes it when the
    /// mouse goes up. The left area grows with the pointer's movement, the right
    /// and bottom ones against it.
    private func areaDivider(for area: DockArea, currentLength: CGFloat, maximum: CGFloat) -> some View {
        let direction: CGFloat = area == .left ? 1 : -1
        return EditorSplitDivider(
            orientation: area.isSide ? .vertical : .horizontal,
            onDragBegan: {
                resizePreview = DockResizePreview(area: area, length: currentLength)
            },
            onDragChanged: { movement in
                resizePreview = DockResizePreview(area: area, length: layout.clampedLength(for: area, proposed: currentLength + direction * movement, maximum: maximum))
            },
            onDragEnded: { movement in
                resizePreview = nil
                layout.resize(area, delta: direction * movement, currentLength: currentLength, maximum: maximum)
                layout.resizeEnded()
            }
        )
    }
}
