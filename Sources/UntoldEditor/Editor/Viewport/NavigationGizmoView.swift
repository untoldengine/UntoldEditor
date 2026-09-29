//
//  NavigationGizmoView.swift
//  UntoldEditor
//
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
import SwiftUI
import UntoldEngine

/// The world's axes as the camera sees them, at the top right of the
/// viewport: a ball with its letter for the positive end of each axis, a ring
/// for the negative one. A click on an end looks along that axis; a drag
/// orbits the camera.
struct NavigationGizmoView: View {
    /// The six ends, the farthest first.
    let handles: [NavigationGizmoHandle]
    let onSelectView: (ViewportProjection) -> Void
    let orbit: NavigationDragHandlers

    @State private var drag: NavigationDrag?

    /// The orbit works in steps of more than a point, so the pointer's travel
    /// is handed over two points at a time.
    static let orbitStep: CGFloat = 2

    var body: some View {
        Canvas { context, size in
            Self.draw(handles, in: &context, size: size)
        }
        .frame(width: NavigationGizmoGeometry.diameter, height: NavigationGizmoGeometry.diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    var current = drag ?? NavigationDrag(clickSlop: InputSystem.clickSlop, minimumStep: Self.orbitStep)
                    let wasDragging = current.isDragging
                    let step = current.step(to: value.translation)
                    drag = current
                    if wasDragging == false, current.isDragging {
                        orbit.began()
                    }
                    if let step {
                        orbit.moved(step)
                    }
                }
                .onEnded { value in
                    let wasDragging = drag?.isDragging == true
                    drag = nil
                    if wasDragging {
                        orbit.ended()
                    } else if let handle = NavigationGizmoGeometry.handle(at: value.startLocation, in: handles) {
                        onSelectView(handle.projection)
                    }
                }
        )
        .help("Click an axis to look along it · Drag to orbit")
        .accessibilityLabel("Navigation gizmo")
    }

    private static func draw(_ handles: [NavigationGizmoHandle], in context: inout GraphicsContext, size: CGSize) {
        let diameter = min(size.width, size.height)
        let scale = diameter / NavigationGizmoGeometry.diameter
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)),
            with: .color(.editorScrimSoft)
        )

        for handle in handles {
            let point = NavigationGizmoGeometry.center(of: handle, diameter: diameter)
            // An end that points away is drawn fainter, so the near ones read first.
            let color = handle.axis.color.opacity(0.55 + 0.45 * Double((handle.depth + 1) / 2))

            if handle.isPositive {
                var arm = Path()
                arm.move(to: center)
                arm.addLine(to: point)
                context.stroke(arm, with: .color(color), lineWidth: 2 * scale)

                let ball = NavigationGizmoGeometry.ballDiameter * scale
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - ball / 2, y: point.y - ball / 2, width: ball, height: ball)),
                    with: .color(color)
                )
                context.draw(
                    Text(handle.axis.letter)
                        .font(.system(size: 9 * scale, weight: .bold))
                        .foregroundColor(.editorTextInverse),
                    at: point
                )
            } else {
                let ring = NavigationGizmoGeometry.ringDiameter * scale
                let outline = Path(ellipseIn: CGRect(x: point.x - ring / 2, y: point.y - ring / 2, width: ring, height: ring))
                context.fill(outline, with: .color(color.opacity(0.35)))
                context.stroke(outline, with: .color(color), lineWidth: 1.5 * scale)
            }
        }
    }
}
