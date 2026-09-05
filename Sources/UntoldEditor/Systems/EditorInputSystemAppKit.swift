//
//  EditorInputSystemAppKit.swift
//  Untold Engine
// Copyright (C) Untold Engine Studios
//
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//  Copyright © 2024 Untold Engine Studios. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Cocoa
    import simd
    import UntoldEngine

    private final class EditorInputTargetViewRef {
        weak var view: NSView?
        /// Set when a left-button press landed on the canvas, so the drag that
        /// follows keeps feeding the canvas even if the pointer leaves it.
        var isTrackingLeftMouseDrag = false
        /// What the in-progress left-button drag does to the camera. Resolved
        /// once when the drag begins so a modifier released mid-drag does not
        /// flip a pan into an orbit halfway through.
        var activeDragAction: CameraDragAction = .none
        /// When the last scroll event navigated the camera. A gap longer than
        /// `InputSystem.scrollSessionGap` starts a new session, which re-anchors
        /// the pivot; inside a session the pivot stays put so an orbit in
        /// progress does not wander.
        var lastScrollNavigationTime: TimeInterval = 0
    }

    private let editorInputTargetViewRef = EditorInputTargetViewRef()

    public extension InputSystem {
        func setupGestureRecognizers(view: NSView) {
            editorInputTargetViewRef.view = view

            // Pinch gesture
            let pinchGesture = NSMagnificationGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            view.addGestureRecognizer(pinchGesture)

            // Pan gesture
            let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))

            view.addGestureRecognizer(panGesture)

            // Click gesture
            let rightClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleRightClick(_:)))
            view.addGestureRecognizer(rightClickGesture)
            rightClickGesture.buttonMask = 0x2 // 0x1 = left, 0x2 = right, 0x4 = middle

            // A left click (no drag) on empty space clears the selection. The
            // click recogniser fails as soon as the pointer moves, so it never
            // competes with the pan recogniser for drags.
            let leftClickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleLeftClick(_:)))
            leftClickGesture.buttonMask = 0x1
            view.addGestureRecognizer(leftClickGesture)
        }

        func setupEventMonitors() {
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.handleFlagsChanged(event)
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.shouldHandleKey(event) == true,
                   event.modifierFlags.contains(.command),
                   event.charactersIgnoringModifiers?.lowercased() == "z"
                {
                    if event.modifierFlags.contains(.shift) {
                        EditorUndoManager.shared.redo()
                    } else {
                        EditorUndoManager.shared.undo()
                    }
                    return nil
                }

                // Let Command-based shortcuts (native menu key equivalents like
                // ⌘1/⌘2/⌘3) reach the menu instead of being eaten as game input.
                if event.modifierFlags.contains(.command) {
                    return event
                }

                // Game/camera keys only belong to the canvas while it is the
                // frontmost view under the pointer; an overlay such as the
                // project gallery must not drive the camera behind it.
                if self?.shouldHandleKey(event) == true,
                   self?.isPointerOverEditorInputView() == true
                {
                    self?.keyPressed(event.keyCode)
                    return nil // Mark event as handled
                }
                return event // Pass event to the system
            }

            NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                // Releases are never gated by hover so a key pressed over the
                // canvas cannot get stuck down after the pointer moves away.
                if self?.shouldHandleKey(event) == true {
                    self?.keyReleased(event.keyCode)
                    return nil // Mark event as handled
                }
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, isEventInsideEditorInputView(event) else {
                    editorInputTargetViewRef.isTrackingLeftMouseDrag = false
                    return event
                }
                editorInputTargetViewRef.isTrackingLeftMouseDrag = true
                leftMouseDown(event)
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                guard editorInputTargetViewRef.isTrackingLeftMouseDrag else {
                    return event
                }
                self?.leftMouseDragged(simd_float2(Float(event.deltaX), Float(event.deltaY)))
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
                // Always clear pressed state, even for presses that started
                // elsewhere, so the canvas never believes a button is held.
                editorInputTargetViewRef.isTrackingLeftMouseDrag = false
                self?.leftMouseUp(event)
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handleMouseScroll(event)
                return event
            }
        }

        private func shouldHandleKey(_: NSEvent) -> Bool {
            if let firstResponder = NSApp.keyWindow?.firstResponder {
                if firstResponder is NSTextView {
                    return false // allow normal text input
                }
            }

            return true // handle the key event
        }

        @objc internal func handlePinch(_ gestureRecognizer: NSMagnificationGestureRecognizer) {
            handlePinchGesture(gestureRecognizer, in: gestureRecognizer.view!)
        }

        @objc internal func handlePan(_ gestureRecognizer: NSPanGestureRecognizer) {
            handlePanGesture(gestureRecognizer, in: gestureRecognizer.view!)
        }

        @objc internal func handleRightClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            mouseRaycast(gestureRecognizer: gestureRecognizer, in: gestureRecognizer.view!)
        }

        @objc internal func handleLeftClick(_ gestureRecognizer: NSClickGestureRecognizer) {
            clearSelectionOnEmptyClick(gestureRecognizer: gestureRecognizer, in: gestureRecognizer.view!)
        }

        func handleMouseScroll(_ event: NSEvent) {
            guard isEventInsideEditorInputView(event) else {
                return
            }

            let rawDelta = simd_float2(Float(event.scrollingDeltaX), Float(event.scrollingDeltaY))
            guard rawDelta.x.isFinite, rawDelta.y.isFinite else {
                return
            }
            let precise = event.hasPreciseScrollingDeltas

            let now = ProcessInfo.processInfo.systemUptime
            if now - editorInputTargetViewRef.lastScrollNavigationTime > InputSystem.scrollSessionGap {
                reanchorSceneCameraTarget()
            }
            editorInputTargetViewRef.lastScrollNavigationTime = now

            // Orbit and zoom lock to the dominant axis, with X inverted and a
            // one-unit dead zone, as they always have.
            var deltaX = rawDelta.x
            var deltaY = rawDelta.y

            if abs(deltaX) < abs(deltaY) {
                deltaX = 0.0
            } else {
                deltaY = 0.0
                deltaX = -1.0 * deltaX
            }

            if abs(deltaX) <= 1.0 {
                deltaX = 0.0
            }

            if abs(deltaY) <= 1.0 {
                deltaY = 0.0
            }

            scrollDelta = 0.01 * simd_float2(deltaX, deltaY)

            switch EditorNavigationSettings.shared.scrollAction(
                shiftPressed: keyState.shiftPressed,
                commandPressed: keyState.commandPressed
            ) {
            case .orbit:
                orbitSceneCamera(byScroll: simd_float2(deltaX, deltaY), precise: precise)
            case .pan:
                // A pan follows both axes at once; no lock or dead zone.
                panSceneCamera(byScroll: rawDelta, precise: precise)
            case .zoom:
                if deltaY != 0.0 {
                    let zoomScale: Float = precise ? 0.025 : 0.15
                    zoomSceneCamera(by: deltaY * zoomScale)
                }
            }
        }

        /// Pan per line of a mouse wheel relative to a point of trackpad scroll;
        /// a wheel reports a few units per notch where a swipe reports points.
        static let scrollWheelPanMultiplier: Float = 10

        /// Pans from a scroll delta. Scroll deltas are document-style (positive Y
        /// means the content moves down the screen) while the view's Y points up,
        /// so Y is flipped before the shared pan moves the scene with the scroll.
        func panSceneCamera(byScroll delta: simd_float2, precise: Bool) {
            let viewDelta = simd_float2(delta.x, -delta.y) * (precise ? 1 : InputSystem.scrollWheelPanMultiplier)
            panSceneCamera(by: viewDelta)
        }

        /// Idle time between scroll events that starts a new navigation session.
        static let scrollSessionGap: TimeInterval = 0.35
        /// Nearest and farthest the pivot may sit ahead of the camera. Beyond the
        /// far limit a wheel notch sweeps a long arc; the default is used instead.
        static let minimumOrbitPivotDistance: Float = 0.25
        static let maximumOrbitPivotDistance: Float = 100
        /// Pivot distance when the view sees neither the ground nor its previous target.
        static let defaultOrbitPivotDistance: Float = 10

        /// Where the camera should orbit, zoom and pan around, always on the view
        /// ray so adopting it never turns the camera: the point the ray meets the
        /// ground plane; failing that (sky, or ground too far) the previous target's
        /// depth if it still lies ahead within range; failing that a default depth.
        static func orbitPivot(eye: simd_float3, forward: simd_float3, currentTarget: simd_float3) -> simd_float3 {
            let forwardLength = simd_length(forward)
            guard forwardLength > 0.0001, forwardLength.isFinite else {
                return currentTarget
            }
            let direction = forward / forwardLength

            if let hit = pickGroundPosition(rayOrigin: eye, rayDirection: direction),
               hit.distance >= minimumOrbitPivotDistance, hit.distance <= maximumOrbitPivotDistance
            {
                return hit.worldPosition
            }

            let depth = simd_dot(currentTarget - eye, direction)
            if depth >= minimumOrbitPivotDistance, depth <= maximumOrbitPivotDistance {
                return eye + direction * depth
            }

            return eye + direction * defaultOrbitPivotDistance
        }

        /// Re-anchors the scene camera's target on `orbitPivot` before a navigation
        /// session. The target is only ever set by a look-at, so flying with WASD,
        /// loading a scene or zooming leaves it where it was, sometimes far away or
        /// behind the camera, and every orbit, zoom and pan step is measured from it.
        func reanchorSceneCameraTarget() {
            let camera = findSceneCamera()
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                return
            }
            let eye = cameraComponent.localPosition
            // The camera looks down its negative Z axis, as the spawn code assumes.
            let pivot = InputSystem.orbitPivot(
                eye: eye,
                forward: -forwardDirectionVector(from: cameraComponent.rotation),
                currentTarget: getCameraTarget(entityId: camera)
            )
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? currentUp : cameraUpDefault
            cameraLookAt(entityId: camera, eye: eye, target: pivot, up: up)
        }

        /// Orbit per point of trackpad scroll, matching the drag orbit's feel.
        static let scrollOrbitSpeedPrecise: Float = 0.005
        /// Orbit per line of a mouse wheel, which reports a few units per notch.
        static let scrollOrbitSpeedWheel: Float = 0.05

        /// Orbits the scene camera around its target from a scroll delta that the
        /// caller has already locked to its dominant axis, with X negated the way
        /// the drag orbit does. Each event re-anchors the orbit on the current
        /// target, as a drag does when it begins, so pans and zooms in between are
        /// respected.
        func orbitSceneCamera(byScroll delta: simd_float2, precise: Bool) {
            guard delta.x.isFinite, delta.y.isFinite, delta.x != 0 || delta.y != 0 else {
                return
            }

            let camera = findSceneCamera()
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let orbitDistance = simd_length(cameraComponent.localPosition - getCameraTarget(entityId: camera))
            setOrbitOffset(
                entityId: camera,
                uTargetOffset: orbitDistance > 0.001 ? orbitDistance : simd_length(cameraComponent.localPosition)
            )
            let speed = precise ? InputSystem.scrollOrbitSpeedPrecise : InputSystem.scrollOrbitSpeedWheel
            orbitAround(entityId: camera, uPosition: delta * speed)
        }

        private func isEventInsideEditorInputView(_ event: NSEvent) -> Bool {
            guard let view = editorInputTargetViewRef.view,
                  let eventWindow = event.window,
                  eventWindow === view.window
            else {
                return false
            }

            return InputSystem.isEditorInputViewFrontmost(at: event.locationInWindow, in: view)
        }

        /// Whether the pointer currently sits over the visible canvas of the key
        /// window. Used to gate key events, which carry no location of their own.
        private func isPointerOverEditorInputView() -> Bool {
            guard let view = editorInputTargetViewRef.view,
                  let window = view.window,
                  NSApp.keyWindow === window
            else {
                return false
            }

            let locationInWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
            return InputSystem.isEditorInputViewFrontmost(at: locationInWindow, in: view)
        }

        /// True only when the view AppKit would deliver a mouse event to at
        /// `locationInWindow` is the canvas (or one of its subviews).
        ///
        /// A bounds check is not enough: SwiftUI overlays hosted in front of the
        /// canvas (project gallery, side panels, toolbars) occupy the same
        /// region, and their scrolling and clicks must not reach the camera.
        /// Hit testing resolves the frontmost view, so those overlays win.
        static func isEditorInputViewFrontmost(at locationInWindow: NSPoint, in view: NSView) -> Bool {
            guard view.isHiddenOrHasHiddenAncestor == false,
                  let window = view.window,
                  let contentView = window.contentView
            else {
                return false
            }

            // hitTest(_:) expects the point in the receiver's superview coordinates.
            let point = contentView.superview?.convert(locationInWindow, from: nil) ?? locationInWindow
            guard let hitView = contentView.hitTest(point) else {
                return false
            }

            return hitView === view || hitView.isDescendant(of: view)
        }

        func handlePinchGesture(_ gestureRecognizer: NSMagnificationGestureRecognizer, in _: NSView) {
            let currentScale = gestureRecognizer.magnification

            if gestureRecognizer.state == .began {
                // store the initial scale
                previousScale = currentScale
                currentPinchGestureState = .began

            } else if gestureRecognizer.state == .changed {
                // determine the direction of the pinch
                let scaleDiff = currentScale - previousScale
                pinchDelta = 3.0 * simd_float3(0.0, 0.0, Float(1.0) * Float(scaleDiff))
                zoomSceneCamera(by: Float(scaleDiff) * 8.0)

                previousScale = currentScale

                currentPinchGestureState = .changed

            } else if gestureRecognizer.state == .ended {
                previousScale = 1.0
                pinchDelta = .init(0, 0, 0)

                currentPinchGestureState = .ended
            }
        }

        private func zoomSceneCamera(by delta: Float) {
            guard delta.isFinite, abs(delta) > 0.0001 else {
                return
            }

            let camera = findSceneCamera()
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let target = getCameraTarget(entityId: camera)
            let eye = cameraComponent.localPosition
            let targetVector = target - eye
            let distance = simd_length(targetVector)

            guard distance > 0.001 else {
                moveCameraAlongAxis(entityId: camera, uDelta: simd_float3(0, 0, delta))
                return
            }

            let minDistance: Float = 0.25
            let maxForwardStep = max(0.0, distance - minDistance)
            let maxBackwardStep = max(5.0, distance * 0.5)
            let clampedDelta: Float = Swift.min(Swift.max(delta, -maxBackwardStep), maxForwardStep)
            guard abs(clampedDelta) > 0.0001 else {
                return
            }

            let direction = simd_normalize(targetVector)
            let newEye = eye + direction * clampedDelta
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? currentUp : cameraUpDefault

            cameraLookAt(entityId: camera, eye: newEye, target: target, up: up)
        }

        /// Slides the camera and its orbit target along the view plane so the
        /// scene follows the cursor (Blender ⇧-drag). The step scales with the
        /// distance to the target so panning feels the same at any zoom level.
        private func panSceneCamera(by delta: simd_float2) {
            guard delta.x.isFinite, delta.y.isFinite, simd_length(delta) > 0.0001 else {
                return
            }

            let camera = findSceneCamera()
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }

            let target = getCameraTarget(entityId: camera)
            let eye = cameraComponent.localPosition
            let rawDistance = simd_length(target - eye)
            guard rawDistance > 0.001 else {
                return
            }
            let distance = Swift.max(rawDistance, 0.25)
            let currentUp = getCameraUp(entityId: camera)
            let up = simd_length(currentUp) > 0.001 ? simd_normalize(currentUp) : cameraUpDefault

            let right = simd_normalize(simd_cross(up, (eye - target) / rawDistance))
            guard right.x.isFinite, right.y.isFinite, right.z.isFinite else {
                return
            }

            // Move the camera opposite to the cursor so the scene tracks it.
            // View y already points up in the (non-flipped) canvas.
            let offset = (-right * delta.x - up * delta.y) * distance * InputSystem.dragPanSpeed
            cameraLookAt(entityId: camera, eye: eye + offset, target: target + offset, up: up)
        }

        /// Dollies toward / away from the orbit target from a drag (Blender
        /// ⌘-drag). Dragging up or right zooms in; the step scales with the
        /// distance to the target.
        private func dragZoomSceneCamera(by delta: simd_float2) {
            let camera = findSceneCamera()
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: camera) else {
                handleError(.noActiveCamera)
                return
            }
            let distance = Swift.max(simd_length(getCameraTarget(entityId: camera) - cameraComponent.localPosition), 0.5)
            let amount = InputSystem.dragZoomAmount(delta: delta, distance: distance)
            zoomSceneCamera(by: amount)
        }

        /// Pan distance per point of drag, as a fraction of the camera-to-target distance.
        static let dragPanSpeed: Float = 0.002

        /// World-space dolly step for a drag delta (in points) at a given
        /// camera-to-target distance. Up / right zooms in.
        static func dragZoomAmount(delta: simd_float2, distance: Float) -> Float {
            guard delta.x.isFinite, delta.y.isFinite else {
                return 0
            }
            return (delta.y + delta.x) * 0.005 * distance
        }

        func mouseRaycast(gestureRecognizer: NSClickGestureRecognizer, in view: NSView) {
            guard editorController?.isEnabled == true else {
                return
            }

            guard scene.get(component: CameraComponent.self, for: findSceneCamera()) != nil else {
                handleError(.noActiveCamera)
                return
            }

            let currentLocation = gestureRecognizer.location(in: view)
            let rayContext = raycastContext(currentLocation: currentLocation, view: view)

            let (entityId, hit) = getRaycastedEntity(currentLocation: currentLocation, view: view)

            if hitGizmoToolAxis(entityId: entityId) {
                return
            }

            gizmoActive = false
            removeGizmo()
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
            activeHitGizmoEntity = .invalid

            if hit {
                if hasComponent(entityId: entityId, componentType: GizmoComponent.self) {
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didSelectEntity(entityId)
                } else if keyState.commandPressed {
                    // Cmd+click selects the top-level asset root, for moving/rotating
                    // the whole imported group at once.
                    let transformEntityId = editableAssetRootEntity(for: entityId)
                    activeEntity = selectableTransformEntity(for: transformEntityId)
                    selectionDelegate?.didSelectEntity(entityId)
                } else if let rayContext,
                          let meshIndex = pickMeshIndexForEntity(
                              entityId: entityId,
                              rayOrigin: rayContext.rayOrigin,
                              rayDirection: rayContext.rayDirection
                          )
                {
                    // Default: click selects the specific child mesh under the cursor.
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didInspectMesh(entityId, meshIndex: meshIndex)
                } else {
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didSelectEntity(entityId)
                }
                selectionDelegate?.resetActiveAxis()

            } else {
                clearViewportSelection()
            }
        }

        /// Left click that lands on nothing: drop the selection so the Inspector
        /// empties and a following ⇧-drag moves the camera instead of an entity.
        /// A click on an entity or a gizmo axis is left to the right-click
        /// selection path and the pan recogniser.
        func clearSelectionOnEmptyClick(gestureRecognizer: NSClickGestureRecognizer, in view: NSView) {
            guard editorController?.isEnabled == true else {
                return
            }

            guard scene.get(component: CameraComponent.self, for: findSceneCamera()) != nil else {
                handleError(.noActiveCamera)
                return
            }

            let currentLocation = gestureRecognizer.location(in: view)
            let (_, hit) = getRaycastedEntity(currentLocation: currentLocation, view: view)
            guard hit == false else {
                return
            }

            gizmoActive = false
            editorController?.activeMode = .none
            editorController?.activeAxis = .none
            activeHitGizmoEntity = .invalid
            clearViewportSelection()
        }

        /// Drops the engine-side selection and tells the editor so the SwiftUI
        /// selection (Inspector, hierarchy highlight) follows.
        func clearViewportSelection() {
            activeEntity = .invalid
            removeGizmo()
            selectionDelegate?.didClearSelection()
        }

        func handlePanGesture(_ gestureRecognizer: NSPanGestureRecognizer, in view: NSView) {
            let currentPanLocation = gestureRecognizer.translation(in: view)
            let currentLocation = gestureRecognizer.location(in: view)

            // Camera is required for any pan handling
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera()) else {
                handleError(.noActiveCamera)
                return
            }

            // Editor is optional; only gates editor-specific logic
            let isEditorEnabled = editorController?.isEnabled ?? (editorController != nil)

            // Decide once, when the drag starts, what it does to the camera.
            // ⇧-drag with a selected entity is reserved for manipulating that
            // entity (in every navigation style) and never moves the camera.
            if gestureRecognizer.state == .began {
                editorInputTargetViewRef.activeDragAction = EditorNavigationSettings.shared.dragAction(
                    shiftPressed: keyState.shiftPressed,
                    commandPressed: keyState.commandPressed,
                    hasSelection: isEditorEnabled && activeEntity != .invalid
                )
            }
            let dragAction = editorInputTargetViewRef.activeDragAction

            // Exit *only* the camera logic, not the entire gesture handler, so
            // entity manipulation keeps receiving mouse deltas.
            if dragAction == .none {
                return
            }

            switch gestureRecognizer.state {
            case .began:
                // Store initial state
                initialPanLocation = currentPanLocation
                currentPanGestureState = .began
                reanchorSceneCameraTarget()
                let orbitDistance = simd_length(cameraComponent.localPosition - getCameraTarget(entityId: findSceneCamera()))
                setOrbitOffset(
                    entityId: findSceneCamera(),
                    uTargetOffset: orbitDistance > 0.001 ? orbitDistance : length(cameraComponent.localPosition)
                )
                cameraControlMode = dragAction == .orbit ? .orbiting : .moving

                // Editor-only: hit-test gizmo if editor/gizmo mode is active
                if gizmoActive, isEditorEnabled {
                    let (hitEntityId, hit) = getRaycastedEntity(currentLocation: currentLocation, view: view)
                    if hit {
                        activeHitGizmoEntity = hitEntityId
                        processGizmoAction(entityId: activeHitGizmoEntity)
                        if let rayContext = raycastContext(currentLocation: currentLocation, view: view) {
                            beginGizmoDrag(
                                ray: GizmoDragRay(
                                    origin: rayContext.rayOrigin,
                                    direction: rayContext.rayDirection
                                )
                            )
                        }
                        if activeEntity != .invalid {
                            EditorUndoManager.shared.beginTransformEdit(entityId: activeEntity)
                        }
                    } else {
                        activeHitGizmoEntity = .invalid
                        editorController?.activeMode = .none
                        editorController?.activeAxis = .none
                    }
                }

            case .changed:
                // Editor-only: process gizmo if we hit one
                if isEditorEnabled {
                    if activeHitGizmoEntity != .invalid,
                       let rayContext = raycastContext(currentLocation: currentLocation, view: view)
                    {
                        queueGizmoDragUpdate(
                            ray: GizmoDragRay(
                                origin: rayContext.rayOrigin,
                                direction: rayContext.rayDirection
                            )
                        )
                    }
                    processGizmoAction(entityId: activeHitGizmoEntity)
                    if activeHitGizmoEntity != .invalid {
                        // While dragging a gizmo, skip camera orbit updates
                        return
                    }
                }

                // Blender-style ⇧ pan / ⌘ zoom use the raw two-axis delta;
                // orbit below keeps its dominant-axis lock.
                if dragAction == .pan || dragAction == .zoom {
                    let rawDelta = simd_float2(
                        Float(currentPanLocation.x - (initialPanLocation?.x ?? currentPanLocation.x)),
                        Float(currentPanLocation.y - (initialPanLocation?.y ?? currentPanLocation.y))
                    )
                    initialPanLocation = currentPanLocation
                    currentPanGestureState = .changed
                    if dragAction == .pan {
                        panSceneCamera(by: rawDelta)
                    } else {
                        dragZoomSceneCamera(by: rawDelta)
                    }
                    return
                }

                // Camera orbit pan (unaffected by editor being absent/disabled)
                var deltaX = currentPanLocation.x - (initialPanLocation?.x ?? currentPanLocation.x)
                var deltaY = currentPanLocation.y - (initialPanLocation?.y ?? currentPanLocation.y)

                // Lock to dominant axis; invert X for your orbit convention
                if abs(deltaX) < abs(deltaY) {
                    deltaX = 0.0
                } else {
                    deltaY = 0.0
                    deltaX = -deltaX
                }

                // Dead zone
                if abs(deltaX) <= 1.0 {
                    deltaX = 0.0
                }
                if abs(deltaY) <= 1.0 {
                    deltaY = 0.0
                }

                panDelta = simd_float2(Float(deltaX), Float(deltaY))
                currentPanGestureState = .changed
                initialPanLocation = currentPanLocation

                orbitAround(entityId: findSceneCamera(), uPosition: InputSystem.shared.panDelta * 0.005)

            case .ended, .cancelled, .failed:
                if isEditorEnabled,
                   activeHitGizmoEntity != .invalid,
                   activeEntity != .invalid
                {
                    EditorUndoManager.shared.commitTransformEdit(entityId: activeEntity)
                }

                // Reset
                panDelta = simd_float2(0, 0)
                initialPanLocation = nil
                currentPanGestureState = .ended
                cameraControlMode = .idle
                editorInputTargetViewRef.activeDragAction = .none
                endGizmoDrag()

            default:
                break
            }
        }

        func leftMouseDragged(_ delta: simd_float2) {
            mouseDeltaX = delta.x
            mouseDeltaY = delta.y

            if abs(mouseDeltaX) < abs(mouseDeltaY) {
                mouseDeltaX = 0.0
            } else {
                mouseDeltaY = 0.0
                // mouseDeltaX = -1.0 * mouseDeltaX
            }

            if abs(mouseDeltaX) <= 1.0 {
                mouseDeltaX = 0.0
            }

            if abs(mouseDeltaY) <= 1.0 {
                mouseDeltaY = 0.0
            }

            lastMouseX = mouseX
            lastMouseY = mouseY

            mouseX += mouseDeltaX
            mouseY += mouseDeltaY

            if mouseDeltaX != 0.0 || mouseDeltaY != 0.0 {
                // mouse is active
                mouseActive = true

            } else {
                //
                mouseActive = false
            }
        }

        func leftMouseDown(_ event: NSEvent) {
            switch event.buttonNumber {
            case 0:
                keyState.leftMousePressed = true
            case 1:
                keyState.rightMousePressed = true
            default:
                break
            }
        }

        func leftMouseUp(_ event: NSEvent) {
            mouseActive = false
            switch event.buttonNumber {
            case 0:
                keyState.leftMousePressed = false
            case 1:
                keyState.rightMousePressed = false
            default:
                break
            }
        }

        func keyPressed(_ keyCode: UInt16) {
            switch keyCode {
            case kVK_ANSI_A:
                keyState.aPressed = true
            case kVK_ANSI_W:
                keyState.wPressed = true
            case kVK_ANSI_D:
                keyState.dPressed = true
            case kVK_ANSI_S:
                keyState.sPressed = true
            case kVK_ANSI_Space:
                keyState.spacePressed = true
            case kVK_ANSI_Q:
                keyState.qPressed = true
            case kVK_ANSI_E:
                keyState.ePressed = true
//        case kVK_ANSI_G:
//            print("G pressed")
            case kVK_ANSI_X:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .x
            case kVK_ANSI_Y:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .y
            case kVK_ANSI_Z:
                guard let editorController else {
                    return
                }
                editorController.activeAxis = .z
            case kVK_ANSI_1:
                break
            case kVK_ANSI_2:
                break
            default:
                break
            }
        }

        func keyReleased(_ keyCode: UInt16) {
            switch keyCode {
            case kVK_ANSI_A:
                keyState.aPressed = false
            case kVK_ANSI_W:
                keyState.wPressed = false
            case kVK_ANSI_D:
                keyState.dPressed = false
            case kVK_ANSI_S:
                keyState.sPressed = false
            case kVK_ANSI_Space:
                keyState.spacePressed = false
            case kVK_ANSI_Q:
                keyState.qPressed = false
            case kVK_ANSI_E:
                keyState.ePressed = false
            case kVK_ANSI_P:
                gameMode = !gameMode
            case kVK_ANSI_R:
                if keyState.shiftPressed {
                    hotReload = !hotReload
                }
            case kVK_ANSI_L:
                if keyState.shiftPressed {
                    visualDebug = !visualDebug
                    currentDebugSelection = DebugSelection.normalOutput
                }
            case kVK_ANSI_1:
                currentDebugSelection = DebugSelection.normalOutput
            case kVK_ANSI_2:
                currentDebugSelection = DebugSelection.iblOutput
            default:
                break
            }
        }

        private func handleFlagsChanged(_ event: NSEvent) {
            // Shift key
            if event.modifierFlags.contains(.shift) {
                keyState.shiftPressed = true
            } else {
                keyState.shiftPressed = false
            }

            // Control key
            if event.modifierFlags.contains(.control) {
                keyState.ctrlPressed = true
            } else {
                keyState.ctrlPressed = false
            }

            // Command key
            if event.modifierFlags.contains(.command) {
                keyState.commandPressed = true
            } else {
                keyState.commandPressed = false
            }
        }

        private func raycastContext(currentLocation: NSPoint, view: NSView) -> (rayOrigin: simd_float3, rayDirection: simd_float3)? {
            guard let cameraComponent = scene.get(component: CameraComponent.self, for: findSceneCamera()) else {
                handleError(.noActiveCamera)
                return nil
            }

            let currentCGPoint = simd_float2(Float(currentLocation.x), Float(currentLocation.y))
            let viewportDimensions = simd_float2(Float(view.bounds.width), Float(view.bounds.height))
            guard viewportDimensions.x > 0, viewportDimensions.y > 0 else {
                return nil
            }

            let rayDirection: simd_float3 = rayDirectionInWorldSpace(
                uMouseLocation: currentCGPoint,
                uViewPortDim: viewportDimensions,
                uPerspectiveSpace: renderInfo.perspectiveSpace,
                uViewSpace: cameraComponent.viewSpace
            )

            guard rayDirection.x.isFinite, rayDirection.y.isFinite, rayDirection.z.isFinite else {
                return nil
            }

            return (cameraComponent.localPosition, rayDirection)
        }

        internal func getRaycastedEntity(currentLocation: NSPoint, view: NSView) -> (entityId: EntityID, hit: Bool) {
            guard let rayContext = raycastContext(currentLocation: currentLocation, view: view) else {
                return (.invalid, false)
            }

            guard let hit = pickEntity(
                rayOrigin: rayContext.rayOrigin,
                rayDirection: rayContext.rayDirection,
                options: ScenePickOptions(isGizmoActive: gizmoActive, backend: .octreeGPUPreferred)
            ) else {
                return (.invalid, false)
            }

            return (hit.entityId, true)
        }
    }
#endif
