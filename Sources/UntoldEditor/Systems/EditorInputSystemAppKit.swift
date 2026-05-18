//
//  EditorInputSystemAppKit.swift
//  Untold Engine
//  Copyright (C) Untold Engine Studios
//  Licensed under the GNU LGPL v3.0 or later.
//  See the LICENSE file or <https://www.gnu.org/licenses/> for details.
//  Copyright © 2024 Untold Engine Studios. All rights reserved.
//

#if os(macOS)
    import AppKit
    import Cocoa
    import simd
    import UntoldEngine

    public extension InputSystem {
        func setupGestureRecognizers(view: NSView) {
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

                if self?.shouldHandleKey(event) == true {
                    self?.keyPressed(event.keyCode)
                    return nil // Mark event as handled
                }
                return event // Pass event to the system
            }

            NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
                if self?.shouldHandleKey(event) == true {
                    self?.keyReleased(event.keyCode)
                    return nil // Mark event as handled
                }
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                self?.leftMouseDown(event)
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
                self?.leftMouseDragged(simd_float2(Float(event.deltaX), Float(event.deltaY)))
                return event
            }

            NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
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

        func handleMouseScroll(_ event: NSEvent) {
            var deltaX: Double = event.scrollingDeltaX
            var deltaY: Double = event.scrollingDeltaY

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

            scrollDelta = 0.01 * simd_float2(Float(deltaX), Float(deltaY))

            if deltaX != 0.0 || deltaY != 0.0 {
                //            if shiftKey{
                //                delta=0.01*simd_float3(0.0,Float(deltaY),0.0)
                //                camera.moveCameraAlongAxis(uDelta: delta)
                //            }

                // camera.moveCameraAlongAxis(uDelta: delta)
            }
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

                previousScale = currentScale

                currentPinchGestureState = .changed

            } else if gestureRecognizer.state == .ended {
                previousScale = 1.0

                currentPinchGestureState = .ended
            }
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
                } else if keyState.shiftPressed,
                          let rayContext,
                          let meshIndex = pickMeshIndexForEntity(
                              entityId: entityId,
                              rayOrigin: rayContext.rayOrigin,
                              rayDirection: rayContext.rayDirection
                          )
                {
                    activeEntity = selectableTransformEntity(for: entityId)
                    selectionDelegate?.didInspectMesh(entityId, meshIndex: meshIndex)
                } else {
                    let transformEntityId = editableAssetRootEntity(for: entityId)
                    activeEntity = selectableTransformEntity(for: transformEntityId)
                    selectionDelegate?.didSelectEntity(entityId)
                }
                selectionDelegate?.resetActiveAxis()

            } else {
                activeEntity = .invalid
                removeGizmo()
            }
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

            // If the editor is active and user is manipulating an entity (e.g., with Shift),
            // exit *only* the camera-orbit logic, not the entire gesture handler.
            if isEditorEnabled,
               activeEntity != .invalid,
               keyState.shiftPressed
            {
                return
            }

            switch gestureRecognizer.state {
            case .began:
                // Store initial state
                initialPanLocation = currentPanLocation
                currentPanGestureState = .began
                setOrbitOffset(entityId: findSceneCamera(), uTargetOffset: length(cameraComponent.localPosition))
                cameraControlMode = .orbiting

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
                        updateGizmoDrag(
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
                if abs(deltaX) <= 1.0 { deltaX = 0.0 }
                if abs(deltaY) <= 1.0 { deltaY = 0.0 }

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
